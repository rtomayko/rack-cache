require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/storage'

describe 'Rack::Cache::Storage' do

  before do
    @storage = Rack::Cache::Storage.new
  end

  it "exposes a meta_store Hash" do
    @storage.should.respond_to :meta_store
  end

  it "exposes a entity_store Hash" do
    @storage.should.respond_to :entity_store
  end

  it "fails when an unknown URI scheme is provided" do
    lambda { @storage.meta_store['foo:/'] }.should.raise
  end

  it "creates a new MetaStore for URI if none exists" do
    @storage.meta_store['heap:/'].
      should.be.kind_of Rack::Cache::MetaStore
  end

  it "returns an existing MetaStore instance for URI that exists" do
    store = @storage.meta_store['heap:/']
    @storage.meta_store['heap:/'].should.be store
  end

  it "creates a new EntityStore for URI if none exists" do
    @storage.entity_store['heap:/'].
      should.be.kind_of Rack::Cache::EntityStore
  end

  it "returns an existing EntityStore instance for URI that exists" do
    store = @storage.entity_store['heap:/']
    @storage.entity_store['heap:/'].should.be store
  end

  it "clears all URI -> store mappings with #clear" do
    meta = @storage.meta_store['heap:/']
    entity = @storage.entity_store['heap:/']
    @storage.clear
    @storage.meta_store['heap:/'].should.not.be meta
    @storage.entity_store['heap:/'].should.not.be entity
  end


  describe 'Heap Store URIs' do
    %w[heap:/ mem:/].each do |uri|
      it "resolves #{uri} meta store URIs" do
        @storage.meta_store[uri].
          should.be.kind_of Rack::Cache::MetaStore
      end
      it "resolves #{uri} entity store URIs" do
        @storage.entity_store[uri].
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
        @storage.meta_store[uri + @temp_dir].
          should.be.kind_of Rack::Cache::MetaStore
      end
      it "resolves #{uri} entity store URIs" do
        @storage.entity_store[uri + @temp_dir].
          should.be.kind_of Rack::Cache::EntityStore
      end
    end
  end

  if ENV['MEMCACHED']

    describe 'MemCache Store URIs' do
      %w[memcache: memcached:].each do |scheme|
        it "resolves #{scheme} meta store URIs" do
          uri = scheme + '//' + ENV['MEMCACHED']
          @storage.meta_store[uri].
            should.be.kind_of Rack::Cache::MetaStore
        end
        it "resolves #{scheme} entity store URIs" do
          uri = scheme + '//' + ENV['MEMCACHED']
          @storage.entity_store[uri].
            should.be.kind_of Rack::Cache::EntityStore
        end
      end
      it 'supports namespaces in memcached: URIs' do
        uri = "memcached://" + ENV['MEMCACHED'] + "/namespace"
        @storage.meta_store[uri].
           should.be.kind_of Rack::Cache::MetaStore
      end
    end

  end

end
