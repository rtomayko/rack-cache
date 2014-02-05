require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/storage'

describe 'Rack::Cache::Storage' do
  before do
    @storage = Rack::Cache::Storage.new
  end

  it "fails when an unknown URI scheme is provided" do
    lambda { @storage.resolve_metastore('foo:/') }.should.raise
  end
  it "creates a new MetaStore for URI if none exists" do
    @storage.resolve_metastore('heap:/').
      should.be.kind_of Rack::Cache::MetaStore
  end
  it "returns an existing MetaStore instance for URI that exists" do
    store = @storage.resolve_metastore('heap:/')
    @storage.resolve_metastore('heap:/').should.be.same_as store
  end
  it "creates a new EntityStore for URI if none exists" do
    @storage.resolve_entitystore('heap:/').
      should.be.kind_of Rack::Cache::EntityStore
  end
  it "returns an existing EntityStore instance for URI that exists" do
    store = @storage.resolve_entitystore('heap:/')
    @storage.resolve_entitystore('heap:/').should.be.same_as store
  end
  it "clears all URI -> store mappings with #clear" do
    meta = @storage.resolve_metastore('heap:/')
    entity = @storage.resolve_entitystore('heap:/')
    @storage.clear
    @storage.resolve_metastore('heap:/').should.not.be.same_as meta
    @storage.resolve_entitystore('heap:/').should.not.be.same_as entity
  end
  it "registers a MetaStore by name" do
    store = Rack::Cache::MetaStore::Heap.new
    @storage.register_metastore(:foo, store)
    @storage.resolve_metastore(:foo).should.be.same_as store
  end
  it "registers an EntityStore by name" do
    store = Rack::Cache::EntityStore::Heap.new
    @storage.register_entitystore(:foo, store)
    @storage.resolve_entitystore(:foo).should.be.same_as store
  end

  describe 'Heap Store URIs' do
    %w[heap:/ mem:/].each do |uri|
      it "resolves #{uri} meta store URIs" do
        @storage.resolve_metastore(uri).
          should.be.kind_of Rack::Cache::MetaStore
      end
      it "resolves #{uri} entity store URIs" do
        @storage.resolve_entitystore(uri).
          should.be.kind_of Rack::Cache::EntityStore
      end
    end
  end

  describe 'Disk Store URIs' do
    before do
      @temp_dir = create_temp_directory
    end
    after do
      remove_entry_secure @temp_dir
      @temp_dir = nil
    end

    %w[file: disk:].each do |uri|
      it "resolves #{uri} meta store URIs" do
        @storage.resolve_metastore(uri + @temp_dir).
          should.be.kind_of Rack::Cache::MetaStore
      end
      it "resolves #{uri} entity store URIs" do
        @storage.resolve_entitystore(uri + @temp_dir).
          should.be.kind_of Rack::Cache::EntityStore
      end
    end
  end

  if have_memcached?

    describe 'MemCache Store URIs' do
      %w[memcache: memcached:].each do |scheme|
        it "resolves #{scheme} meta store URIs" do
          uri = scheme + '//' + ENV['MEMCACHED']
          @storage.resolve_metastore(uri).
            should.be.kind_of Rack::Cache::MetaStore
        end
        it "resolves #{scheme} entity store URIs" do
          uri = scheme + '//' + ENV['MEMCACHED']
          @storage.resolve_entitystore(uri).
            should.be.kind_of Rack::Cache::EntityStore
        end
      end
      it 'supports namespaces in memcached: URIs' do
        uri = "memcached://" + ENV['MEMCACHED'] + "/namespace"
        @storage.resolve_metastore(uri).
           should.be.kind_of Rack::Cache::MetaStore
      end
    end

  end

end
