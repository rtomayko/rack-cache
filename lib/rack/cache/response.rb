require 'set'
require 'rack/cache/headers'

module Rack::Cache

  # A cached Response object. Acts like Rack::Response in many ways
  # but assumes the response is transient.
  class Response
    include Rack::Response::Helpers
    include Rack::Cache::ResponseHeaders

    attr_reader :status, :headers, :body

    def initialize(status, headers, body)
      @status = status
      @headers = headers
      @body = body
    end

    def to_a
      [status, headers, body]
    end

    def dup
      Response.new(status, headers.dup, body)
    end

    def [](header_name)
      headers[header_name]
    end

    def []=(header_name, header_value)
      headers[header_name] = header_value
    end

    def max_age
      if age = headers['X-Max-Age']
        age.to_i
      else
        super || 0
      end
    end

    # The maximum age as calculated by the cache at some point. This
    # value overrides any expiration time specified by the origin
    # server.
    def max_age=(seconds)
      if value
        headers['X-Max-Age'] = seconds.to_i.to_s
      else
        headers.delete('X-Max-Age')
      end
    end

    def cache
      object = dup
      object.cache!
      object
    end

  protected

    # Headers that should not be cached.
    HEADER_BLACKLIST = Set.new(%w[
      Connection
      Keep-Alive
      Proxy-Authenticate
      Proxy-Authorization
      TE
      Trailers
      Transfer-Encoding
      Upgrade
    ])

    # Removes all headers in HEADER_BLACKLIST
    def remove_uncacheable_headers!
      headers.reject! { |name,value| HEADER_BLACKLIST.include?(name) }
      self
    end

    # Returns a Rack response tuple.
    def cache!
      headers['Age'] = age.to_s
      remove_uncacheable_headers!
    end

  public

    # Create a new Response with an object that was cached.
    def self.activate(object)
      response = new(*object)
      response.send :activate!
      response
    end

  protected

    # Called immediately after an object is loaded from the
    # cache. This method recaluculates the response's Age
    # and sets the X-Last-Used header to the time the response
    # was last served by the cache.
    def activate!
      headers['X-Last-Used'] = (date + age).httpdate
      headers.delete('Age')
      headers['Age'] = age.to_i.to_s
    end

  end

end
