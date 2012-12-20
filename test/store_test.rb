require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/store'

shared 'A Rack::Cache::Store Implementation' do

  ###
  # Helpers

  def mock_request(uri, opts)
    env = Rack::MockRequest.env_for(uri, opts || {})
    Rack::Cache::Request.new(env)
  end

  def mock_response(status, headers, body)
    headers ||= {}
    body = Array(body).compact
    Rack::Cache::Response.new(status, headers, body)
  end

  def slurp(body)
    buf = ''
    body.each { |part| buf << part }
    buf
  end

  # Stores an entry for the given request args, returns a url encoded cache key
  # for the request.
  def store_simple_entry(*request_args)
    path, headers = request_args
    @request = mock_request(path || '/test', headers || {})
    @response = mock_response(200, {'Cache-Control' => 'max-age=420'}, ['test'])
    body = @response.body
    cache_key = @store.store(@request, @response)
    @response.body.should.not.be.same_as body
    cache_key
  end

  before do
    @request = mock_request('/', {})
    @response = mock_response(200, {}, ['hello world'])
  end
  after do
    @store = nil
  end

  # Low-level implementation methods ===========================================

  it 'writes a list of negotation tuples with #write' do
    lambda { @store.write('/test', [[{}, {}]]) }.should.not.raise
  end

  it 'reads a list of negotation tuples with #read' do
    @store.write('/test', [[{},{}],[{},{}]])
    tuples = @store.read('/test')
    tuples.should.equal [ [{},{}], [{},{}] ]
  end

  it 'reads an empty list with #read when nothing cached at key' do
    @store.read('/nothing').should.be.empty
  end

  it 'removes entries for key with #purge' do
    @store.write('/test', [[{},{}]])
    @store.read('/test').should.not.be.empty

    @store.purge('/test')
    @store.read('/test').should.be.empty
  end

  it 'succeeds when purging non-existing entries' do
    @store.read('/test').should.be.empty
    @store.purge('/test')
  end

  it 'returns nil from #purge' do
    @store.write('/test', [[{},{}]])
    @store.purge('/test').should.be.nil
    @store.read('/test').should.equal []
  end

  %w[/test http://example.com:8080/ /test?x=y /test?x=y&p=q].each do |key|
    it "can read and write key: '#{key}'" do
      lambda { @store.write(key, [[{},{}]]) }.should.not.raise
      @store.read(key).should.equal [[{},{}]]
    end
  end

  it "can read and write fairly large keys" do
    key = "b" * 4096
    lambda { @store.write(key, [[{},{}]]) }.should.not.raise
    @store.read(key).should.equal [[{},{}]]
  end

  it "allows custom cache keys from block" do
    request = mock_request('/test', {})
    request.env['rack-cache.cache_key'] =
      lambda { |request| request.path_info.reverse }
    @store.cache_key(request).should == 'tset/'
  end

  it "allows custom cache keys from class" do
    request = mock_request('/test', {})
    request.env['rack-cache.cache_key'] = Class.new do
      def self.call(request); request.path_info.reverse end
    end
    @store.cache_key(request).should == 'tset/'
  end

  it 'does not blow up when given a non-marhsalable object with an ALL_CAPS key' do
    store_simple_entry('/bad', { 'SOME_THING' => Proc.new {} })
  end

  # Abstract methods ===========================================================

  it 'stores a cache entry' do
    cache_key = store_simple_entry
    @store.read(cache_key).should.not.be.empty
  end

  it 'sets the X-Content-Digest response header before storing' do
    cache_key = store_simple_entry
    req, res = @store.read(cache_key).first
    res['X-Content-Digest'].should.equal 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'
  end

  it 'finds a stored entry with #lookup' do
    store_simple_entry
    response = @store.lookup(@request)
    response.should.not.be.nil
    response.should.be.kind_of Rack::Cache::Response
  end

  it 'does not find an entry with #lookup when none exists' do
    req = mock_request('/test', {'HTTP_FOO' => 'Foo', 'HTTP_BAR' => 'Bar'})
    @store.lookup(req).should.be.nil
  end

  it "canonizes urls for cache keys" do
    store_simple_entry(path='/test?x=y&p=q')

    hits_req = mock_request(path, {})
    miss_req = mock_request('/test?p=x', {})

    @store.lookup(hits_req).should.not.be.nil
    @store.lookup(miss_req).should.be.nil
  end

  it 'does not find an entry with #lookup when the body does not exist' do
    store_simple_entry
    @response.headers['X-Content-Digest'].should.not.be.nil
    @entitystore.delete(@response.headers['X-Content-Digest'])
    @store.lookup(@request).should.be.nil
  end

  it 'restores response headers properly with #lookup' do
    store_simple_entry
    response = @store.lookup(@request)
    response.headers.
      should.equal @response.headers.merge('Content-Length' => '4')
  end

  it 'restores response body from entity store with #lookup' do
    store_simple_entry
    response = @store.lookup(@request)
    body = '' ; response.body.each {|p| body << p}
    body.should.equal 'test'
  end

  it 'invalidates meta and entity store entries with #invalidate' do
    store_simple_entry
    @store.invalidate(@request)
    response = @store.lookup(@request)
    response.should.be.kind_of Rack::Cache::Response
    response.should.not.be.fresh
  end

  it 'succeeds quietly when #invalidate called with no matching entries' do
    req = mock_request('/test', {})
    @store.invalidate(req)
    @store.lookup(@request).should.be.nil
  end

  it 'gracefully degrades if the cache store stops working' do
    @store = Class.new(Rack::Cache::Store) do
      def delete(*args); nil end
      def lookup(*args); [] end
      def store(*args); nil end
    end.new

    request = mock_request('/test', {})
    response = mock_response(200, {}, ['test'])
    @store.store(request, response)
    response.body.should == ['test']
  end

  # Vary =======================================================================

  it 'does not return entries that Vary with #lookup' do
    req1 = mock_request('/test', {'HTTP_FOO' => 'Foo', 'HTTP_BAR' => 'Bar'})
    req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
    res = mock_response(200, {'Vary' => 'Foo Bar'}, ['test'])
    @store.store(req1, res)

    @store.lookup(req2).should.be.nil
  end

  it 'stores multiple responses for each Vary combination' do
    req1 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
    res1 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 1'])
    key = @store.store(req1, res1)

    req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
    res2 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 2'])
    @store.store(req2, res2)

    req3 = mock_request('/test', {'HTTP_FOO' => 'Baz',   'HTTP_BAR' => 'Boom'})
    res3 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 3'])
    @store.store(req3, res3)

    slurp(@store.lookup(req3).body).should.equal 'test 3'
    slurp(@store.lookup(req1).body).should.equal 'test 1'
    slurp(@store.lookup(req2).body).should.equal 'test 2'

    @store.read(key).length.should.equal 3
  end

  it 'overwrites non-varying responses with #store' do
    req1 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
    res1 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 1'])
    key = @store.store(req1, res1)
    slurp(@store.lookup(req1).body).should.equal 'test 1'

    req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
    res2 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 2'])
    @store.store(req2, res2)
    slurp(@store.lookup(req2).body).should.equal 'test 2'

    req3 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
    res3 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 3'])
    @store.store(req3, res3)
    slurp(@store.lookup(req1).body).should.equal 'test 3'

    @store.read(key).length.should.equal 2
  end
end
