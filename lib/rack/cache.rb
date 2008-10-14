require 'fileutils'
require 'time'
require 'rack'

# Rack Caching Middleware
module Rack::Cache
  require 'rack/cache/request'
  require 'rack/cache/response'
  require 'rack/cache/context'
  require 'rack/cache/storage'

  # Create a new Rack::Cache middleware component
  # that fetches resources from the specified backend
  # application.
  def self.new(backend, options={}, &b)
    Context.new(backend, options={}, &b)
  end
end
