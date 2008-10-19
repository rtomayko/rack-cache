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

    def [](header_name)
      headers[header_name]
    end

    def []=(header_name, header_value)
      headers[header_name] = header_value
    end

    # Called immediately after an object is loaded from the cache.
    def activate!
      headers['Age'] = age.to_i.to_s
    end

    # Return the status, headers, and body in a three-tuple.
    def to_a
      [ status, headers, body ]
    end

    def dup
      object = Response.new(status, headers.dup, body)
      yield object if block_given?
      object
    end

    def freeze
      @headers.freeze
      super
    end

  end

end
