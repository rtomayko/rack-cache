require 'uri'
require 'rack/cache/metastore'
require 'rack/cache/entitystore'

module Rack::Cache

  # Maintains a collection of MetaStore and EntityStore instances keyed by
  # URI. A single instance of this class can be used across a single process
  # to ensure that only a single instance of a backing store is created per
  # unique storage URI.
  class Storage
    def initialize
      @metastores = {}
      @entitystores = {}
    end

    def register_metastore(name, storage_or_uri)
      register_store(@metastores, MetaStore, name, storage_or_uri)
    end

    def resolve_metastore(uri_or_name)
      resolve_store(@metastores, MetaStore, uri_or_name)
    end
    alias_method :resolve_metastore_uri, :resolve_metastore

    def register_entitystore(name, storage_or_uri)
      register_store(@entitystores, EntityStore, name, storage_or_uri)
    end

    def resolve_entitystore(uri_or_name)
      resolve_store(@entitystores, EntityStore, uri_or_name)
    end
    alias_method :resolve_entitystore_uri, :resolve_entitystore

    def clear
      @metastores.clear
      @entitystores.clear
      nil
    end

  private
    def create_store(type, uri)
      if uri.respond_to?(:scheme) || uri.respond_to?(:to_str)
        uri = URI.parse(uri) unless uri.respond_to?(:scheme)
        if type.const_defined?(uri.scheme.upcase)
          klass = type.const_get(uri.scheme.upcase)
          klass.resolve(uri)
        else
          fail "Unknown storage provider: #{uri.to_s}"
        end
      else
        # hack in support for passing a Dalli::Client or Memcached object
        # as the storage URI.
        case
        when defined?(::Dalli) && uri.kind_of?(::Dalli::Client)
          type.const_get(:Dalli).resolve(uri)
        when defined?(::Memcached) && uri.respond_to?(:stats)
          type.const_get(:MemCached).resolve(uri)
        else
          fail "Unknown storage provider: #{uri.to_s}"
        end
      end
    end

    def register_store(stores_hash, type, name, storage_or_uri)
      if stores_hash[name.to_s]
        raise ArgumentError, "%s already registered: %s" % [type, name]
      end

      if storage_or_uri.is_a?(type)
        stores_hash[name.to_s] = storage_or_uri
      else
        stores_hash[name.to_s] = create_store(type, storage_or_uri)
      end
    end

    def resolve_store(stores_hash, type, uri_or_name)
      if stores_hash[uri_or_name.to_s]
        stores_hash[uri_or_name.to_s]
      else
        register_store(stores_hash, type, uri_or_name, create_store(type, uri_or_name))
      end
    end

  public
    @@singleton_instance = new
    def self.instance
      @@singleton_instance
    end
  end

end
