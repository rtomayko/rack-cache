module Rack::Cache

  module Options

    # The cache storage implementation. This should be an
    # instance of one of the classes defined under
    # Rack::Cache::Storage or 
    attr_accessor :storage

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
      hash.each { |name,value| set(name,value) }
      hash
    end

  private

    def initialize_options(options={})
      @storage = Storage::Memory.new
    end

  end

end
