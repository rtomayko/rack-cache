module Rack::Cache

  module Utils
    include Rack::Utils
    extend self
  end

  # A variety of cache storage implementations.
  module Storage

    # Useful base class for 
    class Provider

      def get(key)
        if value = fetch(key)
          value
        elsif block_given?
          put key, yield
        end
      end

      def put(key, value)
        store key, value
      end

      def delete(key)
        store key, nil
      end

      def replace(key, value)
        store key, value if get(key)
      end

    protected

      def fetch(key)
        raise NotImplemented
      end

      def store(key, object)
        raise NotImplemented
      end

    end

    # Stores cached entries in memory using a normal Hash object.
    class Memory < Provider

      def initialize(hashish={})
        @contents = hashish
      end

      def delete(key)
        @contents.delete(key)
      end

    protected

      def fetch(key)
        @contents[key]
      end

      def store(key, object)
        @contents[key] = object
      end

    end


  end

end
