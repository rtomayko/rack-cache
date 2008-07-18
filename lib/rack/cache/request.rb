require 'rack/request'
require 'rack/utils/environment_headers'

module Rack::Cache

  module RequestHelpers

    # A Hash-like object providing access to HTTP headers.
    def headers
      @headers ||= Rack::Utils::EnvironmentHeaders.new(env)
    end

    alias :header :headers

    # Determine if any of the header names provided exists in the
    # request:
    #   if request.header?('Authorization', 'Cookie')
    #     ...
    #   end
    def header?(*names)
      names.any? { |name| headers.include?(name) }
    end

    # Determine if the request's method matches any of the values
    # provided:
    #   if request.request_method?('GET', 'POST')
    #     ...
    #   end
    def request_method?(*methods)
      methods.any? { |method| method.to_s.upcase == request_method }
    end

    alias_method :method?, :request_method?

  end

  class Request < Rack::Request
    include RequestHelpers
  end

end
