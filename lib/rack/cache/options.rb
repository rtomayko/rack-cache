require 'rack/cache/entity_store'

module Rack::Cache

  module Options

    # Enable verbose trace logging. This option is currently enabled by
    # default but is likely to be disabled in a future release.
    attr_accessor :verbose

    # The meta store implementation used to cache response headers. This
    # may be set to an instance of one of the Rack::Cache::MetaStore
    # implementation classes.
    #
    # For example, to use a Disk based meta store:
    #   set :meta_store, Rack::Cache::MetaStore::Disk.new('./cache/meta')
    #
    # If no meta store is specified, the Rack::Cache::MetaStore::Heap
    # implementation is used. This implementation has significant draw-backs
    # so explicit configuration is recommended.
    attr_accessor :meta_store

    # The entity store implementation used to cache response bodies. This
    # may be set to an instance of one of the Rack::Cache::EntityStore
    # implementation classes.
    #
    # For example, to use a Disk based entity store:
    #   set :entity_store, Rack::Cache::EntityStore::Disk.new('./cache/entity')
    #
    # If no entity store is specified, the Rack::Cache::EntityStore::Heap
    # implementation is used. This implementation has significant draw-backs
    # so explicit configuration is recommended.
    attr_accessor :entity_store

    # The number of seconds that a cached object should be considered
    # "fresh" when no explicit freshness information is provided in
    # a response. Note that explicit Cache-Control or Expires headers
    # in a response override this value.
    #
    # Default: 0
    attr_accessor :default_ttl

    # Is verbose logging enabled?
    def verbose?
      @verbose
    end

    # Set an option.
    def set(option, value=self)
      if value == self
        self.options = option.to_hash
      elsif value.kind_of?(Proc)
        (class<<self;self;end).send(:define_method, option) { || value.call }
      else
        send "#{option}=", value
      end
    end

    # Set multiple options.
    def options=(hash={})
      hash.each { |name,value| set(name, value) }
    end

  private

    def initialize_options(options={})
      @verbose = true
      @meta_store = ::Rack::Cache::MetaStore::Heap.new
      @entity_store = ::Rack::Cache::EntityStore::Heap.new
      @default_ttl = 0
    end

  end

end
