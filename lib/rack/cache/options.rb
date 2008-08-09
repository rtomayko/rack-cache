module Rack::Cache

  module Options

    # Enable verbose trace logging.
    #
    # Default: true
    attr_accessor :verbose

    def verbose?
      @verbose
    end

    # The cache storage implementation.
    attr_accessor :storage

    # The number of seconds that a cached object should be considered
    # "fresh" when no explicit freshness information is provided in
    # a response. Note that explicit Cache-Control or Expires headers
    # in a response override this value.
    #
    # Default: 0
    attr_accessor :default_ttl

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
      @storage = Storage::Memory.new
      @default_ttl = 0
    end

  end

end
