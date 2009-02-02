module Rack::Cache
  class Key
    # Implement .call, since it seems like the "Rack-y" thing to do. Plus, it
    # opens the door for cache key generators to just be blocks.
    def self.call(request)
      new(request).generate
    end

    def initialize(request)
      @request = request
    end

    # Generate a normalized cache key for the request.
    def generate
      parts = []
      parts << host + path
      parts << query_string
      parts.compact.join('?')
    end

    private

    # Delegate host info to the request
    def host
      @request.host
    end

    # Delegate path info to the request
    def path
      @request.path_info
    end

    # This probably isn't good enough.
    def query_string
      return nil if @request.params.empty?
      build_query(@request.params.sort)
    end

    # Convert params into a query string without escaping.
    def build_query(params)
      params.map { |tuple| tuple.join('=') }.join('&')
    end
  end
end
