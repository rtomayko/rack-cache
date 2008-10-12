require 'uri'
require 'rack'
require 'rack/cache/metastore'
require 'rack/cache/entitystore'

module Rack::Cache

  # Maintains a collection of MetaStore and EntityStore instances keyed by
  # URL. A single instance of this class can be used across a single process
  # to ensure that a single instance of a backing store is created per unique
  # URI.
  #
  # Store instances are accessed via the meta_store and entity_store
  # attributes. Each is a Hash with a default proc that creates the store
  # instance the first time a new URI is provided.
  #
  #   meta_store['heap:/']
  #   entity_store['file:/var/cache/entity']
  class Storage
    attr_reader :meta_store
    attr_reader :entity_store

    def initialize
      @meta_store =
        Hash.new{ |hash,uri| hash[uri.to_s] = create_store(MetaStore, uri) }
      @entity_store =
        Hash.new{ |hash,uri| hash[uri.to_s] = create_store(EntityStore, uri) }
    end

    # Clear store instances.
    def clear
      @meta_store.clear
      @entity_store.clear
      nil
    end

  protected
    def create_store(type, uri)
      uri = URI.parse(uri) unless uri.respond_to?(:scheme)
      if type.const_defined?(uri.scheme.upcase)
        klass = type.const_get(uri.scheme.upcase)
        klass.resolve(uri)
      else
        fail "Unknown storage provider: #{uri.to_s}"
      end
    end
  end

end
