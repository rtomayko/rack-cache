require 'set'
require 'rack/cache/headers'

module Rack::Cache

  # A cached Response object. Acts like Rack::Response in many ways
  # but assumes the response is transient.
  class Response
    include Rack::Response::Helpers
    include Rack::Cache::ResponseHeaders

    attr_accessor :status, :headers, :body

    def initialize(status, headers, body)
      @status = status
      @headers = headers
      @body = body
      @headers['Date'] ||= Time.now.httpdate
    end

    def to_a
      [ status, headers, body ]
    end

    def dup
      object = Response.new(status, headers.dup, body)
      yield object if block_given?
      object
    end

    def [](header_name)
      headers[header_name]
    end

    def []=(header_name, header_value)
      headers[header_name] = header_value
    end

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

    # Called immediately after an object is loaded from the
    # cache.
    def activate!
      headers['Age'] = age.to_i.to_s
    end

  public

    # Create a new Response with an object that was cached.
    def self.activate(object)
      response = new(*object)
      response.send :activate!
      response
    end

  end

end
