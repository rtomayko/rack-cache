require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/context'
require 'rack/mock_response_fix'

def simple_response(status=200, headers={}, body=['Hello World'])
  Proc.new do |env|
    response = Rack::Response.new(body, status, headers)
    request = Rack::Request.new(env)
    yield request, response if block_given?
    response.finish
  end
end

# Response generated five seconds ago that expires ten seconds later.
def cacheable_response(*args)
  simple_response *args do |req,res|
    # response date is 5 seconds ago; makes expiration tests easier
    res['Expires'] = (Time.now + 5).httpdate
    yield req, res if block_given?
  end
end

def validateable_response(last_modified=Time.now.httpdate)
  simple_response do |req,res|
    res['Last-Modified'] = last_modified
    yield req, res if block_given?
  end
end

describe 'Rack::Cache::Context (Default Configuration)' do

  before(:each) {
    @app = nil
    @backend = nil
    @context = nil
    @request = nil
    @response = nil
    @called = false
  }

  it 'passes on non-GET/HEAD requests' do
    @app = cacheable_response { @called = true }
    post '/'
    @response.should.be.ok
    @called.should.be == true
    @context.should.a.performed :pass
    @response.headers.should.not.include 'Age'
  end

  it 'passes on requests with Authorization' do
    @app = cacheable_response
    get '/',
      'HTTP_AUTHORIZATION' => 'basic foobarbaz'
    @response.should.be.ok
    @context.should.a.performed :pass
    @response.headers.should.not.include 'Age'
  end

  it 'passes on requests with a Cookie' do
    @app = cacheable_response
    get '/', 'HTTP_COOKIE' => 'foo=bar'
    @response.should.be.ok
    @context.should.a.performed :pass
    @response.headers.should.not.include 'Age'
  end

  xit 'passes on requests that include a Cache-Control header set to no-cache' do
    @app = cacheable_response
    get '/', 'HTTP_CACHE_CONTROL' => 'no-cache'
    @response.should.be.ok
    @context.should.a.performed :pass
    @response.headers.should.not.include 'Age'
  end

  it 'fetches response from backend when cache misses' do
    @app = cacheable_response
    get '/'
    @response.should.be.ok
    @context.should.a.performed :miss
    @context.should.a.performed :fetch
    @response.headers.should.not.include 'Age'
  end

  it "does not cache responses with non-cacheable response codes" do
    @app = cacheable_response { |req,res| res.status = 303 }
    get '/'
    @context.should.a.not.performed :store
    @response.status.should.be == 303
    @response.headers.should.not.include 'Age'
  end

  it "does not cache responses with explicit no-store directive" do
    @app = cacheable_response { |req,res| res['Cache-Control'] = "no-store" }
    get '/'
    @response.should.be.ok
    @context.should.a.not.performed :store
    @response.headers.should.not.include 'Age'
  end

  it "caches responses with explicit no-cache directive" do
    @app = cacheable_response { |req,res| res['Cache-Control'] = "no-cache" }
    get '/'
    @response.should.be.ok
    @context.should.a.performed :store
    @response.headers.should.not.include 'Age'
  end

  it 'stores cacheable responses' do
    @app = cacheable_response
    get '/'
    @response.should.be.ok
    @response.body.should.be == 'Hello World'
    @response.headers.should.include 'Date'
    @response['Age'].should.be.nil
    @response['X-Content-Digest'].should.be.nil
    @context.should.a.performed :miss
    @context.should.a.performed :store
    @context.meta_store.to_hash.keys.length.should.be == 1
  end

  it 'stores validateable responses' do
    @app = validateable_response
    get '/'
    @response.should.be.ok
    @response.body.should.be == 'Hello World'
    @context.should.a.performed :miss
    @context.should.a.performed :store
  end

  it 'hits cached/fresh objects' do
    @app =
      cacheable_response do |req,res|
        res['Date'] = (Time.now - 5).httpdate
      end

    @basic_context = Rack::Cache::Context.new(@app)
    @context = @basic_context.clone
    @original = get('/')
    @original.should.be.ok
    @original.headers.should.include 'Date'
    @context.should.a.performed :miss
    @context.should.a.performed :store
    @original.body.should.be == 'Hello World'

    @context = @basic_context.clone
    @cached = get('/')
    @cached.should.be.ok
    @cached['Date'].should.be == @original['Date']
    @cached['Age'].to_i.should.be > 0
    @cached['X-Content-Digest'].should.not.be.nil
    @context.should.a.performed :hit
    @context.should.a.not.performed :fetch
    @cached.body.should.be == 'Hello World'
  end

  it 'fetches full response when cache stale and no validators present' do
    @app =
      cacheable_response do |req,res|
        req.env['HTTP_IF_MODIFIED_SINCE'].should.be.nil 
        req.env['HTTP_IF_NONE_MATCH'].should.be.nil 
      end
    @basic_context = Rack::Cache::Context.new(@app)

    # build initial request
    @context = @basic_context.clone
    @original = get('/')
    @original.should.be.ok
    @original.headers.should.include 'Date'
    @original.headers.should.not.include 'X-Content-Digest'
    @original['Age'].should.be.nil
    @context.should.a.performed :miss
    @context.should.a.performed :store
    @original.body.should.be == 'Hello World'

    # go in and play around with the cached metadata directly ...
    @context.meta_store.to_hash.values.length.should.be == 1
    @context.meta_store.to_hash.values.first.first[1]['Expires'] = Time.now.httpdate

    # build subsequent request; should be found but miss due to freshness
    @context = @basic_context.clone
    @cached = get('/')
    @cached.should.be.ok
    @cached['Age'].to_i.should.be == 0
    @cached['X-Content-Digest'].should.be.nil
    @context.should.a.not.performed :hit
    @context.should.a.not.performed :miss
    @context.should.a.performed :fetch
    @context.should.a.performed :store
    @cached.body.should.be == 'Hello World'
  end

  it 'validates cached responses with Last-Modified header but no freshness information' do
    @last_modified = Time.now.httpdate
    @app =
      validateable_response(@last_modified) do |req,res|
        if req.env['HTTP_IF_MODIFIED_SINCE'] == res['Last-Modified']
          res.status = 304
          res.body = ''
        end
      end
    @basic_context = Rack::Cache::Context.new(@app)

    # build initial request
    @context = @basic_context.clone
    @original = get('/')
    @original.status.should.be == 200
    @original.headers.should.include 'Last-Modified'
    @original.headers.should.not.include 'X-Content-Digest'
    @original.body.should.be == 'Hello World'
    @context.should.a.performed :miss
    @context.should.a.performed :store

    # build subsequent request; should be found but miss due to freshness
    @context = @basic_context.clone
    @cached = get('/')
    @cached.status.should.be == 200
    @cached.headers.should.include 'Last-Modified'
    @cached.headers.should.include 'X-Content-Digest'
    @cached['Age'].to_i.should.be == 0
    @cached.body.should.be == 'Hello World'
    @context.should.a.not.performed :miss
    @context.should.a.performed :fetch
    @context.should.a.performed :store
  end

  it 'replaces cached responses when validation fails' do
    count = 0
    @app =
      validateable_response(Time.now.httpdate) do |req,res|
        case (count+=1)
        when 1
          res.body = 'first response'
        when 2
          res.body = 'second response'
        when 3
          res.body = ''
          res.status = 304
        end
      end
    @basic_context = Rack::Cache::Context.new(@app)

    # first request should fetch from backend and store in cache
    @context = @basic_context.clone
    @first = get('/')
    @first.status.should.be == 200
    @first.body.should.be == 'first response'

    # second request is validated, is invalid, and replaces cached entry
    @context = @basic_context.clone
    @second = get('/')
    @second.status.should.be == 200
    @second.body.should.be == 'second response'

    # third respone is validated, valid, and returns cached entry
    @context = @basic_context.clone
    @second = get('/')
    @second.status.should.be == 200
    @second.body.should.be == 'second response'

    count.should.be == 3
  end

end

describe "Rack::Cache::Context (Logging)" do

  before(:each) {
    @errors = StringIO.new
    @app = simple_response
    @context = Rack::Cache::Context.new(@app)
    @context.errors = @errors
    (class<<@context;self;end).send :public, :log, :trace, :warn, :info
  }

  it 'responds to #log by writing message to #errors' do
    @context.log :test, 'is this thing on?'
    @errors.string.should.be == "[RCL] [TEST] is this thing on?\n"
  end

  it 'allows printf formatting arguments' do
    @context.log :test, '%s %p %i %x', 'hello', 'goodbye', 42, 66
    @errors.string.should.be == "[RCL] [TEST] hello \"goodbye\" 42 42\n"
  end

  it 'responds to #info by logging an :info message' do
    @context.info 'informative stuff'
    @errors.string.should.be == "[RCL] [INFO] informative stuff\n"
  end

  it 'responds to #warn by logging an :warn message' do
    @context.warn 'kinda/maybe bad stuff'
    @errors.string.should.be == "[RCL] [WARN] kinda/maybe bad stuff\n"
  end

  it 'responds to #trace by logging a :trace message' do
    @context.trace 'some insignifacant event'
    @errors.string.should.be == "[RCL] [TRACE] some insignifacant event\n"
  end

  it "doesn't log trace messages when not in verbose mode" do
    @context.verbose = false
    @context.trace 'some insignifacant event'
    @errors.string.should.be == ""
  end

end
