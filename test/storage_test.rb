require_relative 'test_helper'
require 'rack/cache/storage'

describe Rack::Cache::Storage do
  before do
    @storage = Rack::Cache::Storage.new
  end

  it "fails when an unknown URI scheme is provided" do
    lambda { @storage.resolve_metastore_uri('foo:/') }.must_raise
  end

  it "creates a new MetaStore for URI if none exists" do
    @storage.resolve_metastore_uri('heap:/').
      must_be_kind_of Rack::Cache::MetaStore
  end

  it "returns an existing MetaStore instance for URI that exists" do
    store = @storage.resolve_metastore_uri('heap:/')
    @storage.resolve_metastore_uri('heap:/').must_equal store
  end

  it "creates a new EntityStore for URI if none exists" do
    @storage.resolve_entitystore_uri('heap:/').
      must_be_kind_of Rack::Cache::EntityStore
  end

  it "returns an existing EntityStore instance for URI that exists" do
    store = @storage.resolve_entitystore_uri('heap:/')
    @storage.resolve_entitystore_uri('heap:/').must_equal store
  end

  it "clears all URI -> store mappings with #clear" do
    meta = @storage.resolve_metastore_uri('heap:/')
    entity = @storage.resolve_entitystore_uri('heap:/')
    @storage.clear
    @storage.resolve_metastore_uri('heap:/').object_id.wont_equal meta.object_id
    @storage.resolve_entitystore_uri('heap:/').object_id.wont_equal entity.object_id
  end

  describe 'Noop Store URIs' do
    it "resolves Noop meta store URIs" do
      @storage.resolve_entitystore_uri('noop:/').
        must_be_kind_of Rack::Cache::EntityStore::Noop
    end
  end

  describe 'Heap Store URIs' do
    %w[heap:/ mem:/].each do |uri|
      it "resolves #{uri} meta store URIs" do
        @storage.resolve_metastore_uri(uri).
          must_be_kind_of Rack::Cache::MetaStore
      end
      it "resolves #{uri} entity store URIs" do
        @storage.resolve_entitystore_uri(uri).
          must_be_kind_of Rack::Cache::EntityStore
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
        @storage.resolve_metastore_uri(uri + @temp_dir).
          must_be_kind_of Rack::Cache::MetaStore
      end

      it "resolves #{uri} entity store URIs" do
        @storage.resolve_entitystore_uri(uri + @temp_dir).
          must_be_kind_of Rack::Cache::EntityStore
      end
    end
  end

  if have_memcached?

    describe 'MemCache Store URIs' do
      %w[memcache: memcached:].each do |scheme|
        it "resolves #{scheme} meta store URIs" do
          uri = scheme + '//' + ENV['MEMCACHED']
          @storage.resolve_metastore_uri(uri).
            must_be_kind_of Rack::Cache::MetaStore
        end

        it "resolves #{scheme} entity store URIs" do
          uri = scheme + '//' + ENV['MEMCACHED']
          @storage.resolve_entitystore_uri(uri).
            must_be_kind_of Rack::Cache::EntityStore
        end
      end

      it 'supports namespaces in memcached: URIs' do
        uri = "memcached://" + ENV['MEMCACHED'] + "/namespace"
        @storage.resolve_metastore_uri(uri).
           must_be_kind_of Rack::Cache::MetaStore
      end
    end
  end
end
