require "#{File.dirname(__FILE__)}/spec_setup"

describe 'Rack::Cache::Context' do

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
      res['Date'] = (Time.now - 5).httpdate
      res['Expires'] = (Time.now + 5).httpdate
      yield req,res if block_given?
    end
  end

  def validatable_response(*args)
    simple_resource *args do |req,res|
      res['Date'] = (Time.now - 5).httpdate
      res['Last-Modified'] = res['Date']
      yield req,res if block_given?
    end
  end

  before(:each) {
    @app = nil
    @backend = nil
    @context = nil
    @request = nil
    @response = nil
    @called = false
  }

  it 'passes non GET/HEAD requests to the backend' do
    @app = cacheable_response { @called = true }
    post '/', 'rack.run_once' => true
    @response.should.be.ok
    @called.should.be == true
    @context.should.a.performed :pass
    @response.headers.should.not.include 'Age'
    @context.storage.get('/').should.be.nil
  end

  it 'passes requests with an Authorization header to the backend' do
  end

  it 'fetches response from backend when nothing cached' do
    @app = simple_response { @called = true }
    get('/').should.be.ok
    @called.should.be == true
  end

  it 'stores cacheable responses to GET requests' do
    @app = cacheable_response

    @original = get('/')
    @original.should.be.ok
    @original.headers.should.include 'Date'
    @original.headers['Age'].should.be == '0'

    @cached = get('/')
    @cached.should.be.ok
    @cached['Date'].should.be == @original.headers['Date']
    @cached['Age'].to_i.should.be > 0
  end

protected

  def request(method, uri='/', opts={})
    opts = { 'rack.run_once' => false }.merge(opts)
    @backend ||= @app
    @context ||= Rack::Cache::Context.new(@backend)
    yield @context if block_given?
    @request = Rack::MockRequest.new(@context)
    @response = @request.send(method, uri, opts)
    @response.should.not.be.nil
    @response
  end

  def get(*args, &b)
    request(:get, *args, &b)
  end

  def post(*args, &b)
    request(:post, *args, &b)
  end

private

  def method_missing(method_name, *args, &b)
    if @response
      @response.send method_name, *args, &b
    else
      super
    end
  end


end
