require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/context'

describe 'Rack::Cache::Context' do
  before(:each) { setup_cache_context }
  after(:each)  { teardown_cache_context }

  it 'passes on non-GET/HEAD requests' do
    respond_with 200
    post '/'

    app.should.be.called
    response.should.be.ok
    cache.should.a.performed :pass
    response.headers.should.not.include 'Age'
  end

  it 'passes on requests with Authorization' do
    respond_with 200
    get '/', 'HTTP_AUTHORIZATION' => 'basic foobarbaz'

    app.should.be.called
    response.should.be.ok
    cache.should.a.performed :pass
    response.headers.should.not.include 'Age'
  end

  it 'passes on requests with a Cookie' do
    respond_with 200
    get '/', 'HTTP_COOKIE' => 'foo=bar'

    response.should.be.ok
    app.should.be.called
    cache.should.a.performed :pass
    response.headers.should.not.include 'Age'
  end

  it 'caches requests when Cache-Control request header set to no-cache' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate
    get '/', 'HTTP_CACHE_CONTROL' => 'no-cache'

    response.should.be.ok
    cache.should.a.performed :store
    response.headers.should.not.include 'Age'
  end

  it 'fetches response from backend when cache misses' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate
    get '/'

    response.should.be.ok
    cache.should.a.performed :miss
    cache.should.a.performed :fetch
    response.headers.should.not.include 'Age'
  end

  [(201..202),(204..206),(303..305),(400..403),(405..409),(411..417),(500..505)].each do |range|
    range.each do |response_code|
      it "does not cache #{response_code} responses" do
        respond_with response_code, 'Expires' => (Time.now + 5).httpdate
        get '/'

        cache.should.a.not.performed :store
        response.status.should.be == response_code
        response.headers.should.not.include 'Age'
      end
    end
  end

  it "does not cache responses with explicit no-store directive" do
    respond_with 200,
      'Expires' => (Time.now + 5).httpdate,
      'Cache-Control' => 'no-store'
    get '/'

    response.should.be.ok
    cache.should.a.not.performed :store
    response.headers.should.not.include 'Age'
  end

  it 'does not cache responses without freshness information or a validator' do
    respond_with 200
    get '/'

    response.should.be.ok
    cache.should.a.not.performed :store
  end

  it "caches responses with explicit no-cache directive" do
    respond_with 200,
      'Expires' => (Time.now + 5).httpdate,
      'Cache-Control' => 'no-cache'
    get '/'

    response.should.be.ok
    cache.should.a.performed :store
    response.headers.should.not.include 'Age'
  end

  it 'caches responses with an Expiration header' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate
    get '/'

    response.should.be.ok
    response.body.should.be == 'Hello World'
    response.headers.should.include 'Date'
    response['Age'].should.be.nil
    response['X-Content-Digest'].should.be.nil
    cache.should.a.performed :miss
    cache.should.a.performed :store
    cache.meta_store.to_hash.keys.length.should.be == 1
  end

  it 'caches responses with a max-age directive' do
    respond_with 200, 'Cache-Control' => 'max-age=5'
    get '/'

    response.should.be.ok
    response.body.should.be == 'Hello World'
    response.headers.should.include 'Date'
    response['Age'].should.be.nil
    response['X-Content-Digest'].should.be.nil
    cache.should.a.performed :miss
    cache.should.a.performed :store
    cache.meta_store.to_hash.keys.length.should.be == 1
  end

  it 'caches responses with a Last-Modified validator but no freshness information' do
    respond_with 200, 'Last-Modified' => Time.now.httpdate
    get '/'

    response.should.be.ok
    response.body.should.be == 'Hello World'
    cache.should.a.performed :miss
    cache.should.a.performed :store
  end

  it 'caches responses with an ETag validator but no freshness information' do
    respond_with 200, 'Etag' => '"123456"'
    get '/'

    response.should.be.ok
    response.body.should.be == 'Hello World'
    cache.should.a.performed :miss
    cache.should.a.performed :store
  end

  it 'hits cached response with Expires header' do
    respond_with 200,
      'Date' => (Time.now - 5).httpdate,
      'Expires' => (Time.now + 5).httpdate

    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Date'
    cache.should.a.performed :miss
    cache.should.a.performed :store
    response.body.should.be == 'Hello World'

    get '/'
    response.should.be.ok
    app.should.not.be.called
    response['Date'].should.be == responses.first['Date']
    response['Age'].to_i.should.be > 0
    response['X-Content-Digest'].should.not.be.nil
    cache.should.a.performed :hit
    cache.should.a.not.performed :fetch
    response.body.should.be == 'Hello World'
  end

  it 'hits cached response with max-age directive' do
    respond_with 200,
      'Date' => (Time.now - 5).httpdate,
      'Cache-Control' => 'max-age=10'

    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Date'
    cache.should.a.performed :miss
    cache.should.a.performed :store
    response.body.should.be == 'Hello World'

    get '/'
    response.should.be.ok
    app.should.not.be.called
    response['Date'].should.be == responses.first['Date']
    response['Age'].to_i.should.be > 0
    response['X-Content-Digest'].should.not.be.nil
    cache.should.a.performed :hit
    cache.should.a.not.performed :fetch
    response.body.should.be == 'Hello World'
  end

  it 'fetches full response when cache stale and no validators present' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate

    # build initial request
    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Date'
    response.headers.should.not.include 'X-Content-Digest'
    response['Age'].should.be.nil
    cache.should.a.performed :miss
    cache.should.a.performed :store
    response.body.should.be == 'Hello World'

    # go in and play around with the cached metadata directly ...
    cache.meta_store.to_hash.values.length.should.be == 1
    cache.meta_store.to_hash.values.first.first[1]['Expires'] = Time.now.httpdate

    # build subsequent request; should be found but miss due to freshness
    get '/'
    app.should.be.called
    response.should.be.ok
    response['Age'].to_i.should.be == 0
    response['X-Content-Digest'].should.be.nil
    cache.should.a.not.performed :hit
    cache.should.a.not.performed :miss
    cache.should.a.performed :fetch
    cache.should.a.performed :store
    response.body.should.be == 'Hello World'
  end

  it 'validates cached responses with Last-Modified and no freshness information' do
    timestamp = Time.now.httpdate
    respond_with do |req,res|
      res['Last-Modified'] = timestamp
      if req.env['HTTP_IF_MODIFIED_SINCE'] == timestamp
        res.status = 304
        res.body = []
      end
    end

    # build initial request
    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Last-Modified'
    response.headers.should.not.include 'X-Content-Digest'
    response.body.should.be == 'Hello World'
    cache.should.a.performed :miss
    cache.should.a.performed :store

    # build subsequent request; should be found but miss due to freshness
    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Last-Modified'
    response.headers.should.include 'X-Content-Digest'
    response['Age'].to_i.should.be == 0
    response['X-Origin-Status'].should.be == '304'
    response.body.should.be == 'Hello World'
    cache.should.a.not.performed :miss
    cache.should.a.performed :fetch
    cache.should.a.performed :store
  end

  it 'validates cached responses with ETag and no freshness information' do
    timestamp = Time.now.httpdate
    respond_with do |req,res|
      res['ETAG'] = '"12345"'
      if req.env['HTTP_IF_NONE_MATCH'] == res['Etag']
        res.status = 304
        res.body = []
      end
    end

    # build initial request
    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Etag'
    response.headers.should.not.include 'X-Content-Digest'
    response.body.should.be == 'Hello World'
    cache.should.a.performed :miss
    cache.should.a.performed :store

    # build subsequent request; should be found but miss due to freshness
    get '/'
    app.should.be.called
    response.should.be.ok
    response.headers.should.include 'Etag'
    response.headers.should.include 'X-Content-Digest'
    response['Age'].to_i.should.be == 0
    response['X-Origin-Status'].should.be == '304'
    response.body.should.be == 'Hello World'
    cache.should.a.not.performed :miss
    cache.should.a.performed :fetch
    cache.should.a.performed :store
  end

  it 'replaces cached responses when validation results in non-304 response' do
    timestamp = Time.now.httpdate
    count = 0
    respond_with do |req,res|
      res['Last-Modified'] = timestamp
      case (count+=1)
      when 1 ; res.body = 'first response'
      when 2 ; res.body = 'second response'
      when 3
        res.body = []
        res.status = 304
      end
    end

    # first request should fetch from backend and store in cache
    get '/'
    response.status.should.be == 200
    response.body.should.be == 'first response'

    # second request is validated, is invalid, and replaces cached entry
    get '/'
    response.status.should.be == 200
    response.body.should.be == 'second response'

    # third respone is validated, valid, and returns cached entry
    get '/'
    response.status.should.be == 200
    response.body.should.be == 'second response'

    count.should.be == 3
  end

end
