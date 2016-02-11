require_relative 'test_helper'
require 'rack/cache/meta_store'
require 'rack/cache/entity_store'

module RackCacheMetaStoreImplementation
  def self.included(base)
    base.class_eval do

      ###
      # Helpers
      def mock_request(uri, opts)
        env = Rack::MockRequest.env_for(uri, opts || {})
        Rack::Cache::Request.new(env)
      end

      def mock_response(status, headers, body)
        headers ||= {}
        Rack::Cache::Response.new(status, headers, body)
      end

      def slurp(body)
        buf = ''
        body.each { |part| buf << part }
        buf
      end

      # Stores an entry for the given request args, returns a url encoded cache key
      # for the request.
      def store_simple_entry(path=nil, headers=nil, body=['test'])
        @request = mock_request(path || '/test', headers || {})
        @response = mock_response(200, {'Cache-Control' => 'max-age=420'}, body)
        body = @response.body
        cache_key = @store.store(@request, @response, @entity_store)

        # atm we always read back the body from the cache, this is a workaround to deal with
        # bodies that can only be read once
        @response.body.object_id.wont_equal body.object_id

        cache_key
      end

      before do
        @request = mock_request('/', {})
        @response = mock_response(200, {}, ['hello world'])
      end

      after do
        @store = nil
        @entity_store = nil
      end

      # Low-level implementation methods ===========================================

      it 'writes a list of negotation tuples with #write' do
        @store.write('/test', [[{}, {}]])
      end

      it 'reads a list of negotation tuples with #read' do
        @store.write('/test', [[{},{}],[{},{}]])
        tuples = @store.read('/test')
        tuples.must_equal [ [{},{}], [{},{}] ]
      end

      it 'reads an empty list with #read when nothing cached at key' do
        assert @store.read('/nothing').empty?
      end

      it 'removes entries for key with #purge' do
        @store.write('/test', [[{},{}]])
        refute @store.read('/test').empty?

        @store.purge('/test')
        assert @store.read('/test').empty?
      end

      it 'succeeds when purging non-existing entries' do
        assert @store.read('/test').empty?
        @store.purge('/test')
      end

      it 'returns nil from #purge' do
        @store.write('/test', [[{},{}]])
        @store.purge('/test').must_equal nil
        @store.read('/test').must_equal []
      end

      %w[/test http://example.com:8080/ /test?x=y /test?x=y&p=q].each do |key|
        it "can read and write key: '#{key}'" do
          @store.write(key, [[{},{}]])
          @store.read(key).must_equal [[{},{}]]
        end
      end

      it "can read and write fairly large keys" do
        key = "b" * 4096
        @store.write(key, [[{},{}]])
        @store.read(key).must_equal [[{},{}]]
      end

      it "allows custom cache keys from block" do
        request = mock_request('/test', {})
        request.env['rack-cache.cache_key'] =
          lambda { |request| request.path_info.reverse }
        @store.cache_key(request).must_equal 'tset/'
      end

      it "allows custom cache keys from class" do
        request = mock_request('/test', {})
        request.env['rack-cache.cache_key'] = Class.new do
          def self.call(request); request.path_info.reverse end
        end
        @store.cache_key(request).must_equal 'tset/'
      end

      it 'does not blow up when given a non-marhsalable object with an ALL_CAPS key' do
        store_simple_entry('/bad', { 'SOME_THING' => Proc.new {} })
      end

      # Abstract methods ===========================================================

      it 'stores a cache entry' do
        cache_key = store_simple_entry
        refute @store.read(cache_key).empty?
      end

      it 'can handle objects that can only be read once' do
        io = StringIO.new("TEST")
        store_simple_entry nil, nil, io

        # was stored correctly in entity store
        key = @response.headers.fetch('X-Content-Digest')
        @entity_store.read(key).must_equal "TEST"

        # io is closed, so that file descriptors are released
        assert io.closed?

        # renderd body is the same content as the cache
        @response.body.to_a.must_equal ["TEST"]
      end

      it 'sets the X-Content-Digest response header before storing' do
        cache_key = store_simple_entry
        req, res = @store.read(cache_key).first
        res['X-Content-Digest'].must_equal 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'
      end

      it 'finds a stored entry with #lookup' do
        store_simple_entry
        response = @store.lookup(@request, @entity_store)
        refute response.nil?
        response.class.must_equal  Rack::Cache::Response
      end

      it 'does not find an entry with #lookup when none exists' do
        req = mock_request('/test', {'HTTP_FOO' => 'Foo', 'HTTP_BAR' => 'Bar'})
        @store.lookup(req, @entity_store).must_equal nil
      end

      it "canonizes urls for cache keys" do
        store_simple_entry(path='/test?x=y&p=q')

        hits_req = mock_request(path, {})
        miss_req = mock_request('/test?p=x', {})

        @store.lookup(hits_req, @entity_store).wont_equal nil
        @store.lookup(miss_req, @entity_store).must_equal nil
      end

      it 'does not find an entry with #lookup when the body does not exist' do
        store_simple_entry
        refute @response.headers['X-Content-Digest'].nil?
        @entity_store.purge(@response.headers['X-Content-Digest'])
        @store.lookup(@request, @entity_store).must_equal nil
      end

      it 'restores response headers properly with #lookup' do
        store_simple_entry
        response = @store.lookup(@request, @entity_store)
        response.headers.
          must_equal @response.headers.merge('Content-Length' => '4')
      end

      it 'restores response body from entity store with #lookup' do
        store_simple_entry
        response = @store.lookup(@request, @entity_store)
        body = '' ; response.body.each {|p| body << p}
        body.must_equal 'test'
      end

      it 'invalidates meta and entity store entries with #invalidate' do
        store_simple_entry
        @store.invalidate(@request, @entity_store)
        response = @store.lookup(@request, @entity_store)
        response.class.must_equal  Rack::Cache::Response
        refute response.fresh?
      end

      it 'succeeds quietly when #invalidate called with no matching entries' do
        req = mock_request('/test', {})
        @store.invalidate(req, @entity_store)
        @store.lookup(@request, @entity_store).must_equal nil
      end

      it 'gracefully degrades if the cache store stops working' do
        @store = Class.new(Rack::Cache::MetaStore) do
          def purge(*args); nil end
          def read(*args); [] end
          def write(*args); nil end
        end.new
        @entity_store = Class.new(Rack::Cache::EntityStore) do
          def exists?(*args); false end
          def open(*args); nil end
          def read(*args); nil end
          def write(*args); nil end
          def purge(*args); nil end
        end.new

        request = mock_request('/test', {})
        response = mock_response(200, {}, ['test'])
        @store.store(request, response, @entity_store)
        response.body.must_equal ['test']
      end

      # Vary =======================================================================

      it 'does not return entries that Vary with #lookup' do
        req1 = mock_request('/test', {'HTTP_FOO' => 'Foo', 'HTTP_BAR' => 'Bar'})
        req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
        res = mock_response(200, {'Vary' => 'Foo Bar'}, ['test'])
        @store.store(req1, res, @entity_store)

        @store.lookup(req2, @entity_store).must_equal nil
      end

      it 'stores multiple responses for each Vary combination' do
        req1 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
        res1 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 1'])
        key = @store.store(req1, res1, @entity_store)

        req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
        res2 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 2'])
        @store.store(req2, res2, @entity_store)

        req3 = mock_request('/test', {'HTTP_FOO' => 'Baz',   'HTTP_BAR' => 'Boom'})
        res3 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 3'])
        @store.store(req3, res3, @entity_store)

        slurp(@store.lookup(req3, @entity_store).body).must_equal 'test 3'
        slurp(@store.lookup(req1, @entity_store).body).must_equal 'test 1'
        slurp(@store.lookup(req2, @entity_store).body).must_equal 'test 2'

        @store.read(key).length.must_equal 3
      end

      it 'overwrites non-varying responses with #store' do
        req1 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
        res1 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 1'])
        key = @store.store(req1, res1, @entity_store)
        slurp(@store.lookup(req1, @entity_store).body).must_equal 'test 1'

        req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
        res2 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 2'])
        @store.store(req2, res2, @entity_store)
        slurp(@store.lookup(req2, @entity_store).body).must_equal 'test 2'

        req3 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
        res3 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 3'])
        @store.store(req3, res3, @entity_store)
        slurp(@store.lookup(req1, @entity_store).body).must_equal 'test 3'

        @store.read(key).length.must_equal 2
      end
    end
  end
end

describe Rack::Cache::MetaStore do
  {read: [1], write: [1,2], purge: [1]}.each do |method, args|
    it "has not implemented #{method}" do
      assert_raises NotImplementedError do
        Rack::Cache::MetaStore.new.send(method, *args)
      end
    end
  end

  describe 'Heap' do
    before do
      @store = Rack::Cache::MetaStore::Heap.new
      @entity_store = Rack::Cache::EntityStore::Heap.new
    end
    include RackCacheMetaStoreImplementation
  end

  describe 'Disk' do
    before do
      @temp_dir = create_temp_directory
      @store = Rack::Cache::MetaStore::Disk.new("#{@temp_dir}/meta")
      @entity_store = Rack::Cache::EntityStore::Disk.new("#{@temp_dir}/entity")
    end
    after do
      remove_entry_secure @temp_dir
    end
    include RackCacheMetaStoreImplementation
  end

  need_memcached 'metastore tests' do
    describe 'MemCached' do
      before do
        @temp_dir = create_temp_directory
        $memcached.flush
        @store = Rack::Cache::MetaStore::MemCached.new($memcached)
        @entity_store = Rack::Cache::EntityStore::Heap.new
      end
      include RackCacheMetaStoreImplementation
    end

    describe 'options parsing' do
      before do
        uri = URI.parse("memcached://#{ENV['MEMCACHED']}/meta_ns1?show_backtraces=true")
        @memcached_metastore = Rack::Cache::MetaStore::MemCached.resolve uri
      end

      it 'passes options from uri' do
        @memcached_metastore.cache.instance_variable_get(:@options)[:show_backtraces].must_equal true
      end

      it 'takes namespace into account' do
        @memcached_metastore.cache.instance_variable_get(:@options)[:prefix_key].must_equal 'meta_ns1'
      end
    end
  end

  need_dalli 'metastore tests' do
    describe 'Dalli' do
      before do
        @temp_dir = create_temp_directory
        $dalli.flush_all
        @store = Rack::Cache::MetaStore::Dalli.new($dalli)
        @entity_store = Rack::Cache::EntityStore::Heap.new
      end
      include RackCacheMetaStoreImplementation
    end

    describe 'options parsing' do
      before do
        uri = URI.parse("memcached://#{ENV['MEMCACHED']}/meta_ns1?show_backtraces=true")
        @dalli_metastore = Rack::Cache::MetaStore::Dalli.resolve uri
      end

      it 'passes options from uri' do
        @dalli_metastore.cache.instance_variable_get(:@options)[:show_backtraces].must_equal true
      end

      it 'takes namespace into account' do
        @dalli_metastore.cache.instance_variable_get(:@options)[:namespace].must_equal 'meta_ns1'
      end
    end
  end

  need_java 'entity store testing' do
    module Rack::Cache::AppEngine
      module MC
        class << (Service = {})
          def contains(key); include?(key); end
          def get(key); self[key]; end;
          def put(key, value, ttl = nil)
            self[key] = value
          end
        end
      end
    end

    describe 'GAEStore' do
      before :each do
        Rack::Cache::AppEngine::MC::Service.clear
        @store = Rack::Cache::MetaStore::GAEStore.new
        @entity_store = Rack::Cache::EntityStore::Heap.new
      end
      include RackCacheMetaStoreImplementation
    end
  end
end
