require 'rack/utils'

module Rack::Utils
  # A facade over a Rack Environment Hash that gives access to headers
  # using their normal RFC 2616 names.

  class EnvironmentHeaders
    include Enumerable

    # Create the facade over the given Rack Environment Hash.
    def initialize(env)
      @env = env
    end

    # Return the value of the specified header. The +header_name+ should
    # be as specified by RFC 2616 (e.g., "Content-Type", "Accept", etc.)
    def [](header_name)
      @env[env_name(header_name)]
    end

    # Set the value of the specified header. The +header_name+ should
    # be as specified by RFC 2616 (e.g., "Content-Type", "Accept", etc.)
    def []=(header_name, value)
      @env[env_name(header_name)] = value
    end

    # Determine if the underlying Rack Environment includes a header
    # of the given name.
    def include?(header_name)
      @env.include?(env_name(header_name))
    end

    # Iterate over all headers yielding a (name, value) tuple to the
    # block. Rack Environment keys that do not map to an header are not
    # included.
    def each
      @env.each do |key,value|
        next unless key =~ /^(HTTP_|CONTENT_)/
        yield header_name(key), value
      end
    end

    # Delete the entry in the underlying Rack Environment that corresponds
    # to the given RFC 2616 header name.
    def delete(header_name)
      @env.delete(env_name(header_name))
    end

    # Return the underlying Rack Environment Hash.
    def to_env
      @env
    end

    alias_method :to_hash, :to_env

  private

    # Return the Rack Environment key for the given RFC 2616 header name.
    def env_name(header_name)
      case header_name = header_name.upcase
      when 'CONTENT-TYPE'   then 'CONTENT_TYPE'
      when 'CONTENT-LENGTH' then 'CONTENT_LENGTH'
      else "HTTP_#{header_name.tr('-', '_')}"
      end
    end

    # Return the RFC 2616 header name for the given Rack Environment key.
    def header_name(env_name)
      env_name.
        sub(/^HTTP_/, '').
        downcase.
        capitalize.
        gsub(/_(.)/) { '-' + $1.upcase }
    end

  end

end
