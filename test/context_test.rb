require_relative 'test_helper'
require 'rack/cache/context'

describe Rack::Cache::Context do
  before { setup_cache_context }
  after  { teardown_cache_context }

  it 'passes options to the underlying stores' do
    app = CacheContextHelpers::FakeApp.new(200, {}, ['foo'])
    context = Rack::Cache::Context.new(app, foo: 'bar')
    entity_options = context.entitystore.instance_variable_get('@options')
    meta_options = context.metastore.instance_variable_get('@options')

    entity_options[:foo].must_equal('bar')
    meta_options[:foo].must_equal('bar')
  end

  it 'passes on non-GET/HEAD requests' do
    respond_with 200
    post '/'

    assert app.called?
    assert response.ok?
    cache.trace.must_include :pass
    response.headers.wont_include 'Age'
  end

  it 'passes on rack-cache.force-pass' do
    respond_with 200
    get '/', {"rack-cache.force-pass" => true}

    assert app.called?
    assert response.ok?
    cache.trace.must_equal [:pass]
    response.headers.wont_include 'Age'
  end

  it "passes on options requests" do
    respond_with 200
    request "options", '/'

    assert app.called?
    assert response.ok?
    cache.trace.must_include :pass
  end

  it "doesnt invalidate on options requests" do
    respond_with 200
    request "options", '/'

    assert app.called?
    assert response.ok?
    cache.trace.wont_include :invalidate
  end

  %w[post put delete].each do |request_method|
    it "invalidates on #{request_method} requests" do
      respond_with 200
      request request_method, '/'

      assert app.called?
      assert response.ok?
      cache.trace.must_include :invalidate
      cache.trace.must_include :pass
    end
  end

  it 'does not cache with Authorization request header and non public response' do
    respond_with 200, 'ETag' => '"FOO"'
    get '/', 'HTTP_AUTHORIZATION' => 'basic foobarbaz'

    assert app.called?
    assert response.ok?
    response.headers['Cache-Control'].must_equal 'private'
    cache.trace.must_include :miss
    cache.trace.wont_include :store
    response.headers.wont_include 'Age'
  end

  it 'does cache with Authorization request header and public response' do
    respond_with 200, 'Cache-Control' => 'public', 'ETag' => '"FOO"'
    get '/', 'HTTP_AUTHORIZATION' => 'basic foobarbaz'

    assert app.called?
    assert response.ok?
    cache.trace.must_include :miss
    cache.trace.must_include :store
    cache.trace.wont_include :ignore
    response.headers.must_include 'Age'
    response.headers['Cache-Control'].must_equal 'public'
  end

  it 'does not cache with Cookie header and non public response' do
    respond_with 200, 'ETag' => '"FOO"'
    get '/', 'HTTP_COOKIE' => 'foo=bar'

    assert app.called?
    assert response.ok?
    response.headers['Cache-Control'].must_equal 'private'
    cache.trace.must_include :miss
    cache.trace.wont_include :store
    response.headers.wont_include 'Age'
  end

  it 'does not cache requests with a Cookie header' do
    respond_with 200
    get '/', 'HTTP_COOKIE' => 'foo=bar'

    assert response.ok?
    assert app.called?
    cache.trace.must_include :miss
    cache.trace.wont_include :store
    response.headers.wont_include 'Age'
    response.headers['Cache-Control'].must_equal 'private'
  end

  it 'does remove Set-Cookie response header from a cacheable response' do
    respond_with 200, 'Cache-Control' => 'public', 'ETag' => '"FOO"', 'Set-Cookie' => 'TestCookie=OK'
    get '/'

    assert app.called?
    assert response.ok?
    cache.trace.must_include :store
    cache.trace.must_include :ignore
    response.headers['Set-Cookie'].must_be_nil
  end

  it 'does remove all configured ignore_headers from a cacheable response' do
    respond_with 200, 'Cache-Control' => 'public', 'ETag' => '"FOO"', 'SET-COOKIE' => 'TestCookie=OK', 'X-Strip-Me' => 'Secret'
    get '/', 'rack-cache.ignore_headers' => ['set-cookie', 'x-strip-me']

    assert app.called?
    assert response.ok?
    cache.trace.must_include :store
    cache.trace.must_include :ignore
    response.headers['Set-Cookie'].must_be_nil
    response.headers['x-strip-me'].must_be_nil
  end

  it 'does not remove Set-Cookie response header from a private response' do
    respond_with 200, 'Cache-Control' => 'private', 'Set-Cookie' => 'TestCookie=OK'
    get '/'

    assert app.called?
    assert response.ok?
    cache.trace.wont_include :store
    cache.trace.wont_include :ignore
    response.headers['Set-Cookie'].must_equal 'TestCookie=OK'
  end

  it 'responds with 304 when If-Modified-Since matches Last-Modified' do
    timestamp = Time.now.httpdate
    respond_with do |req,res|
      res.status = 200
      res['Last-Modified'] = timestamp
      res['Content-Type'] = 'text/plain'
      res.body = ['Hello World']
    end

    get '/',
      'HTTP_IF_MODIFIED_SINCE' => timestamp
    assert app.called?
    response.status.must_equal 304
    response.original_headers.wont_include 'Content-Length'
    response.original_headers.wont_include 'Content-Type'
    assert response.body.empty?
    cache.trace.must_include :miss
    cache.trace.must_include :store
  end

  it 'responds with 304 when If-None-Match matches ETag' do
    respond_with do |req,res|
      res.status = 200
      res['ETag'] = '12345'
      res['Content-Type'] = 'text/plain'
      res.body = ['Hello World']
    end

    get '/',
      'HTTP_IF_NONE_MATCH' => '12345'
    assert app.called?
    response.status.must_equal 304
    response.original_headers.wont_include 'Content-Length'
    response.original_headers.wont_include 'Content-Type'
    response.headers.must_include 'ETag'
    assert response.body.empty?
    cache.trace.must_include :miss
    cache.trace.must_include :store
  end

  it 'responds with 304 only if If-None-Match and If-Modified-Since both match' do
    timestamp = Time.now

    respond_with do |req,res|
      res.status = 200
      res['ETag'] = '12345'
      res['Last-Modified'] = timestamp.httpdate
      res['Content-Type'] = 'text/plain'
      res.body = ['Hello World']
    end

    # Only etag matches
    get '/',
      'HTTP_IF_NONE_MATCH' => '12345', 'HTTP_IF_MODIFIED_SINCE' => (timestamp - 1).httpdate
    assert app.called?
    response.status.must_equal 200

    # Only last-modified matches
    get '/',
      'HTTP_IF_NONE_MATCH' => '1234', 'HTTP_IF_MODIFIED_SINCE' => timestamp.httpdate
    assert app.called?
    response.status.must_equal 200

    # Both matches
    get '/',
      'HTTP_IF_NONE_MATCH' => '12345', 'HTTP_IF_MODIFIED_SINCE' => timestamp.httpdate
    assert app.called?
    response.status.must_equal 304
  end

  it 'validates private responses cached on the client' do
    respond_with do |req,res|
      etags = req.env['HTTP_IF_NONE_MATCH'].to_s.split(/\s*,\s*/)
      if req.env['HTTP_COOKIE'] == 'authenticated'
        res['Cache-Control'] = 'private, no-store'
        res['ETag'] = '"private tag"'
        if etags.include?('"private tag"')
          res.status = 304
        else
          res.status = 200
          res['Content-Type'] = 'text/plain'
          res.body = ['private data']
        end
      else
        res['ETag'] = '"public tag"'
        if etags.include?('"public tag"')
          res.status = 304
        else
          res.status = 200
          res['Content-Type'] = 'text/plain'
          res.body = ['public data']
        end
      end
    end

    get '/'
    assert app.called?
    response.status.must_equal 200
    response.headers['ETag'].must_equal '"public tag"'
    response.body.must_equal 'public data'
    cache.trace.must_include :miss
    cache.trace.must_include :store

    get '/', 'HTTP_COOKIE' => 'authenticated'
    assert app.called?
    response.status.must_equal 200
    response.headers['ETag'].must_equal '"private tag"'
    response.body.must_equal 'private data'
    cache.trace.must_include :stale
    cache.trace.must_include :invalid
    cache.trace.wont_include :store

    get '/',
      'HTTP_IF_NONE_MATCH' => '"public tag"'
    assert app.called?
    response.status.must_equal 304
    response.headers['ETag'].must_equal '"public tag"'
    cache.trace.must_include :stale
    cache.trace.must_include :valid
    cache.trace.must_include :store

    get '/',
      'HTTP_IF_NONE_MATCH' => '"private tag"',
      'HTTP_COOKIE' => 'authenticated'
    assert app.called?
    response.status.must_equal 304
    response.headers['ETag'].must_equal '"private tag"'
    cache.trace.must_include :valid
    cache.trace.wont_include :store
  end

  it 'stores responses when no-cache request directive present' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate

    get '/', 'HTTP_CACHE_CONTROL' => 'no-cache'
    assert response.ok?
    cache.trace.must_include :store
    response.headers.must_include 'Age'
  end

  it 'reloads responses when cache hits but no-cache request directive present ' +
     'when allow_reload is set true' do
    count = 0
    respond_with 200, 'Cache-Control' => 'max-age=10000' do |req,res|
      count+= 1
      res.body = (count == 1) ? ['Hello World'] : ['Goodbye World']
    end

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :store

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :fresh

    get '/',
      'rack-cache.allow_reload' => true,
      'HTTP_CACHE_CONTROL' => 'no-cache'
    assert response.ok?
    response.body.must_equal 'Goodbye World'
    cache.trace.must_include :reload
    cache.trace.must_include :store
  end

  it 'does not reload responses when allow_reload is set false (default)' do
    count = 0
    respond_with 200, 'Cache-Control' => 'max-age=10000' do |req,res|
      count+= 1
      res.body = (count == 1) ? ['Hello World'] : ['Goodbye World']
    end

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :store

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :fresh

    get '/',
      'rack-cache.allow_reload' => false,
      'HTTP_CACHE_CONTROL' => 'no-cache'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.wont_include :reload

    # test again without explicitly setting the allow_reload option to false
    get '/',
      'HTTP_CACHE_CONTROL' => 'no-cache'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.wont_include :reload
  end

  it 'revalidates fresh cache entry when max-age request directive is exceeded ' +
     'when allow_revalidate option is set true' do
    count = 0
    respond_with do |req,res|
      count+= 1
      res['Cache-Control'] = 'max-age=10000'
      res['ETag'] = count.to_s
      res.body = (count == 1) ? ['Hello World'] : ['Goodbye World']
    end

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :store

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :fresh

    get '/',
      'rack-cache.allow_revalidate' => true,
      'HTTP_CACHE_CONTROL' => 'max-age=0'
    assert response.ok?
    response.body.must_equal 'Goodbye World'
    cache.trace.must_include :stale
    cache.trace.must_include :invalid
    cache.trace.must_include :store
  end

  it 'returns a stale cache entry when max-age request directive is exceeded ' +
     'when allow_revalidate and fault_tolerant options are set to true and ' +
     'the remote server returns a connection error' do
    count = 0
    respond_with do |req, res|
      count += 1
      raise Timeout::Error, 'Connection failed' if count == 2
      res['Cache-Control'] = 'max-age=10000'
      res['ETag'] = count.to_s
      res.body = (count == 1) ? ['Hello World'] : ['Goodbye World']
    end

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :store

    get '/',
      'rack-cache.allow_revalidate' => true,
      'rack-cache.fault_tolerant' => true,
      'HTTP_CACHE_CONTROL' => 'max-age=0'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :stale
    cache.trace.must_include :connnection_failed

    # Once the server comes back, the request should be revalidated.
    get '/',
      'rack-cache.allow_revalidate' => true,
      'HTTP_CACHE_CONTROL' => 'max-age=0'
    assert response.ok?
    response.body.must_equal 'Goodbye World'
    cache.trace.must_include :stale
    cache.trace.must_include :invalid
    cache.trace.must_include :store
  end

  it 'does not revalidate fresh cache entry when enable_revalidate option is set false (default)' do
    count = 0
    respond_with do |req,res|
      count+= 1
      res['Cache-Control'] = 'max-age=10000'
      res['ETag'] = count.to_s
      res.body = (count == 1) ? ['Hello World'] : ['Goodbye World']
    end

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :store

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :fresh

    get '/',
      'rack-cache.allow_revalidate' => false,
      'HTTP_CACHE_CONTROL' => 'max-age=0'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.wont_include :stale
    cache.trace.wont_include :invalid
    cache.trace.must_include :fresh

    # test again without explicitly setting the allow_revalidate option to false
    get '/',
      'HTTP_CACHE_CONTROL' => 'max-age=0'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.wont_include :stale
    cache.trace.wont_include :invalid
    cache.trace.must_include :fresh
  end
  it 'fetches response from backend when cache misses' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate
    get '/'

    assert response.ok?
    cache.trace.must_include :miss
    response.headers.must_include 'Age'
  end

  [(201..202),(204..206),(303..305),(400..403),(405..409),(411..417),(500..505)].each do |range|
    range.each do |response_code|
      it "does not cache #{response_code} responses" do
        respond_with response_code, 'Expires' => (Time.now + 5).httpdate
        get '/'

        cache.trace.wont_include :store
        response.status.must_equal response_code
        response.headers.wont_include 'Age'
      end
    end
  end

  it "does not cache responses with explicit no-store directive" do
    respond_with 200,
      'Expires' => (Time.now + 5).httpdate,
      'Cache-Control' => 'no-store'
    get '/'

    assert response.ok?
    cache.trace.wont_include :store
    response.headers.wont_include 'Age'
  end

  it 'does not cache responses without freshness information or a validator' do
    respond_with 200
    get '/'

    assert response.ok?
    cache.trace.wont_include :store
  end

  it "caches responses with explicit no-cache directive" do
    respond_with 200,
      'Expires' => (Time.now + 5).httpdate,
      'Cache-Control' => 'no-cache'
    get '/'

    assert response.ok?
    cache.trace.must_include :store
    response.headers.must_include 'Age'
  end

  it 'caches responses with an Expiration header' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate
    get '/'

    assert response.ok?
    response.body.must_equal 'Hello World'
    response.headers.must_include 'Date'
    refute response['Age'].nil?
    refute response['X-Content-Digest'].nil?
    cache.trace.must_include :miss
    cache.trace.must_include :store
    cache.metastore.to_hash.keys.length.must_equal 1
  end

  it 'caches responses with a max-age directive' do
    respond_with 200, 'Cache-Control' => 'max-age=5'
    get '/'

    assert response.ok?
    response.body.must_equal 'Hello World'
    response.headers.must_include 'Date'
    refute response['Age'].nil?
    refute response['X-Content-Digest'].nil?
    cache.trace.must_include :miss
    cache.trace.must_include :store
    cache.metastore.to_hash.keys.length.must_equal 1
  end

  it 'caches responses with a s-maxage directive' do
    respond_with 200, 'Cache-Control' => 's-maxage=5'
    get '/'

    assert response.ok?
    response.body.must_equal 'Hello World'
    response.headers.must_include 'Date'
    refute response['Age'].nil?
    refute response['X-Content-Digest'].nil?
    cache.trace.must_include :miss
    cache.trace.must_include :store
    cache.metastore.to_hash.keys.length.must_equal 1
  end

  it 'caches responses with a Last-Modified validator but no freshness information' do
    respond_with 200, 'Last-Modified' => Time.now.httpdate
    get '/'

    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :miss
    cache.trace.must_include :store
  end

  it 'caches responses with an ETag validator but no freshness information' do
    respond_with 200, 'ETag' => '"123456"'
    get '/'

    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :miss
    cache.trace.must_include :store
  end

  it 'hits cached response with Expires header' do
    respond_with 200,
      'Date' => (Time.now - 5).httpdate,
      'Expires' => (Time.now + 5).httpdate

    get '/'
    assert app.called?
    assert response.ok?
    response.headers.must_include 'Date'
    cache.trace.must_include :miss
    cache.trace.must_include :store
    response.body.must_equal 'Hello World'

    get '/'
    assert response.ok?
    refute app.called?
    response['Date'].must_equal responses.first['Date']
    response['Age'].to_i.must_be :>, 0
    refute response['X-Content-Digest'].nil?
    cache.trace.must_include :fresh
    cache.trace.wont_include :store
    response.body.must_equal 'Hello World'
  end

  it 'hits cached response with max-age directive' do
    respond_with 200,
      'Date' => (Time.now - 5).httpdate,
      'Cache-Control' => 'max-age=10'

    get '/'
    assert app.called?
    assert response.ok?
    response.headers.must_include 'Date'
    cache.trace.must_include :miss
    cache.trace.must_include :store
    response.body.must_equal 'Hello World'

    get '/'
    assert response.ok?
    refute app.called?
    response['Date'].must_equal responses.first['Date']
    response['Age'].to_i.must_be :>, 0
    refute response['X-Content-Digest'].nil?
    cache.trace.must_include :fresh
    cache.trace.wont_include :store
    response.body.must_equal 'Hello World'
  end

  it 'hits cached response with s-maxage directive' do
    respond_with 200,
      'Date' => (Time.now - 5).httpdate,
      'Cache-Control' => 's-maxage=10, max-age=0'

    get '/'
    assert app.called?
    assert response.ok?
    response.headers.must_include 'Date'
    cache.trace.must_include :miss
    cache.trace.must_include :store
    response.body.must_equal 'Hello World'

    get '/'
    assert response.ok?
    refute app.called?
    response['Date'].must_equal responses.first['Date']
    response['Age'].to_i.must_be :>, 0
    refute response['X-Content-Digest'].nil?
    cache.trace.must_include :fresh
    cache.trace.wont_include :store
    response.body.must_equal 'Hello World'
  end

  it 'assigns default_ttl when response has no freshness information' do
    respond_with 200

    get '/', 'rack-cache.default_ttl' => 10
    assert app.called?
    assert response.ok?
    cache.trace.must_include :miss
    cache.trace.must_include :store
    response.body.must_equal 'Hello World'
    response['Cache-Control'].must_include 's-maxage=10'

    get '/', 'rack-cache.default_ttl' => 10
    assert response.ok?
    refute app.called?
    cache.trace.must_include :fresh
    cache.trace.wont_include :store
    response.body.must_equal 'Hello World'
  end

  it 'does not assign default_ttl when response has must-revalidate directive' do
    respond_with 200,
      'Cache-Control' => 'must-revalidate'

    get '/', 'rack-cache.default_ttl' => 10
    assert app.called?
    assert response.ok?
    cache.trace.must_include :miss
    cache.trace.wont_include :store
    response['Cache-Control'].wont_include 's-maxage'
    response.body.must_equal 'Hello World'
  end

  it 'fetches full response when cache stale and no validators present' do
    respond_with 200, 'Expires' => (Time.now + 5).httpdate

    # build initial request
    get '/'
    assert app.called?
    assert response.ok?
    response.headers.must_include 'Date'
    response.headers.must_include 'X-Content-Digest'
    response.headers.must_include 'Age'
    cache.trace.must_include :miss
    cache.trace.must_include :store
    response.body.must_equal 'Hello World'

    # go in and play around with the cached metadata directly ...
    # XXX find some other way to do this
    hash = cache.metastore.to_hash
    hash.values.length.must_equal 1
    entries = Marshal.load(hash.values.first)
    entries.length.must_equal 1
    req, res = entries.first
    res['Expires'] = (Time.now - 1).httpdate
    hash[hash.keys.first] = Marshal.dump([[req, res]])

    # build subsequent request; should be found but miss due to freshness
    get '/'
    assert app.called?
    assert response.ok?
    response['Age'].to_i.must_equal 0
    response.headers.must_include 'X-Content-Digest'
    cache.trace.must_include :stale
    cache.trace.wont_include :fresh
    cache.trace.wont_include :miss
    cache.trace.must_include :store
    response.body.must_equal 'Hello World'
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
    assert app.called?
    assert response.ok?
    response.headers.must_include 'Last-Modified'
    response.headers.must_include 'X-Content-Digest'
    response.body.must_equal 'Hello World'
    cache.trace.must_include :miss
    cache.trace.must_include :store
    cache.trace.wont_include :stale

    # build subsequent request; should be found but miss due to freshness
    get '/'
    assert app.called?
    assert response.ok?
    response.headers.must_include 'Last-Modified'
    response.headers.must_include 'X-Content-Digest'
    response['Age'].to_i.must_equal 0
    response.body.must_equal 'Hello World'
    cache.trace.must_include :stale
    cache.trace.must_include :valid
    cache.trace.must_include :store
    cache.trace.wont_include :miss
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
    assert app.called?
    assert response.ok?
    response.headers.must_include 'ETag'
    response.headers.must_include 'X-Content-Digest'
    response.body.must_equal 'Hello World'
    cache.trace.must_include :miss
    cache.trace.must_include :store

    # build subsequent request; should be found but miss due to freshness
    get '/'
    assert app.called?
    assert response.ok?
    response.headers.must_include 'ETag'
    response.headers.must_include 'X-Content-Digest'
    response['Age'].to_i.must_equal 0
    response.body.must_equal 'Hello World'
    cache.trace.must_include :stale
    cache.trace.must_include :valid
    cache.trace.must_include :store
    cache.trace.wont_include :miss
  end

  it 'replaces cached responses when validation results in non-304 response' do
    timestamp = Time.now.httpdate
    count = 0
    respond_with do |req,res|
      res['Last-Modified'] = timestamp
      case (count+=1)
      when 1 ; res.body = ['first response']
      when 2 ; res.body = ['second response']
      when 3
        res.body = []
        res.status = 304
      end
    end

    # first request should fetch from backend and store in cache
    get '/'
    response.status.must_equal 200
    response.body.must_equal 'first response'

    # second request is validated, is invalid, and replaces cached entry
    get '/'
    response.status.must_equal 200
    response.body.must_equal 'second response'

    # third respone is validated, valid, and returns cached entry
    get '/'
    response.status.must_equal 200
    response.body.must_equal 'second response'

    count.must_equal 3
  end

  it 'stores HEAD as original_method on HEAD requests' do
    respond_with do |req,res|
      res.status = 200
      res.body = []
      req.request_method.must_equal 'GET'
      req.env['rack.methodoverride.original_method'].must_equal 'HEAD'
    end

    head '/'
    assert app.called?
    response.body.must_equal ''
  end

  it 'passes HEAD requests through directly on pass' do
    respond_with do |req,res|
      res.status = 200
      res.body = []
      req.request_method.must_equal 'HEAD'
    end

    head '/', 'HTTP_EXPECT' => 'something ...'
    assert app.called?
    response.body.must_equal ''
  end

  it 'uses cache to respond to HEAD requests when fresh' do
    respond_with do |req,res|
      res['Cache-Control'] = 'max-age=10'
      res.body = ['Hello World']
      req.request_method.wont_equal 'HEAD'
    end

    get '/'
    assert app.called?
    response.status.must_equal 200
    response.body.must_equal 'Hello World'

    head '/'
    refute app.called?
    response.status.must_equal 200
    response.body.must_equal ''
    response['Content-Length'].must_equal 'Hello World'.length.to_s
  end

  it 'invalidates cached responses on POST' do
    respond_with do |req,res|
      if req.request_method == 'GET'
        res.status = 200
        res['Cache-Control'] = 'public, max-age=500'
        res.body = ['Hello World']
      elsif req.request_method == 'POST'
        res.status = 303
        res['Location'] = '/'
        res.headers.delete('Cache-Control')
        res.body = []
      end
    end

    # build initial request to enter into the cache
    get '/'
    assert app.called?
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :miss
    cache.trace.must_include :store

    # make sure it is valid
    get '/'
    refute app.called?
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :fresh

    # now POST to same URL
    post '/'
    assert app.called?
    assert response.redirect?
    response['Location'].must_equal '/'
    cache.trace.must_include :invalidate
    cache.trace.must_include :pass
    response.body.must_equal ''

    # now make sure it was actually invalidated
    get '/'
    assert app.called?
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :stale
    cache.trace.must_include :invalid
    cache.trace.must_include :store
  end

  describe 'with responses that include a Vary header' do
    before do
      count = 0
      respond_with 200 do |req,res|
        res['Vary'] = 'Accept User-Agent Foo'
        res['Cache-Control'] = 'max-age=10'
        res['X-Response-Count'] = (count+=1).to_s
        res.body = [req.env['HTTP_USER_AGENT']]
      end
    end

    it 'serves from cache when headers match' do
      get '/',
        'HTTP_ACCEPT' => 'text/html',
        'HTTP_USER_AGENT' => 'Bob/1.0'
      assert response.ok?
      response.body.must_equal 'Bob/1.0'
      cache.trace.must_include :miss
      cache.trace.must_include :store

      get '/',
        'HTTP_ACCEPT' => 'text/html',
        'HTTP_USER_AGENT' => 'Bob/1.0'
      assert response.ok?
      response.body.must_equal 'Bob/1.0'
      cache.trace.must_include :fresh
      cache.trace.wont_include :store
      response.headers.must_include 'X-Content-Digest'
    end

    it 'stores multiple responses when headers differ' do
      get '/',
        'HTTP_ACCEPT' => 'text/html',
        'HTTP_USER_AGENT' => 'Bob/1.0'
      assert response.ok?
      response.body.must_equal 'Bob/1.0'
      response['X-Response-Count'].must_equal '1'

      get '/',
        'HTTP_ACCEPT' => 'text/html',
        'HTTP_USER_AGENT' => 'Bob/2.0'
      cache.trace.must_include :miss
      cache.trace.must_include :store
      response.body.must_equal 'Bob/2.0'
      response['X-Response-Count'].must_equal '2'

      get '/',
        'HTTP_ACCEPT' => 'text/html',
        'HTTP_USER_AGENT' => 'Bob/1.0'
      cache.trace.must_include :fresh
      response.body.must_equal 'Bob/1.0'
      response['X-Response-Count'].must_equal '1'

      get '/',
        'HTTP_ACCEPT' => 'text/html',
        'HTTP_USER_AGENT' => 'Bob/2.0'
      cache.trace.must_include :fresh
      response.body.must_equal 'Bob/2.0'
      response['X-Response-Count'].must_equal '2'

      get '/',
        'HTTP_USER_AGENT' => 'Bob/2.0'
      cache.trace.must_include :miss
      response.body.must_equal 'Bob/2.0'
      response['X-Response-Count'].must_equal '3'
    end
  end

  it 'passes if there was a metastore exception' do
    respond_with 200, 'Cache-Control' => 'max-age=10000' do |req,res|
      res.body = ['Hello World']
    end

    get '/'
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :store

    get '/' do |cache|
      cache.expects(:metastore).raises Timeout::Error
    end
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :pass

    post '/' do |cache|
      cache.expects(:metastore).raises Timeout::Error
    end
    assert response.ok?
    response.body.must_equal 'Hello World'
    cache.trace.must_include :pass
  end

  it 'logs to rack.logger if available' do
    logger = Class.new do
      attr_reader :logged_level

      def info(message)
        @logged_level = "info"
      end
    end.new

    respond_with 200
    get '/', 'rack.logger' => logger
    assert response.ok?
    logger.logged_level.must_equal "info"
  end
end
