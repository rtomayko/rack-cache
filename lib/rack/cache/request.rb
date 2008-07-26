require 'rack/request'
require 'rack/cache/headers'
require 'rack/utils/environment_headers'

module Rack::Cache

  class Request < Rack::Request
    include Rack::Cache::RequestHeaders

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

end
