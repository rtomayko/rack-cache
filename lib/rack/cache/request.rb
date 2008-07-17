require 'rack/request'

module Rack::Cache

  class Request < Rack::Request

    alias verb request_method

    def header(name)
      request.env['HTTP_' + name.upcase.gsub('-', '_')]
    end

    def header?(*names)
      names.any? { |name| header(name) }
    end

    def request_method?(*methods)
      methods.any? { |method| method.to_s.upcase == request_method }
    end

  end

end
