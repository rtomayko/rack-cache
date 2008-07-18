require 'fileutils'
require 'time'
require 'rack'


# Rack Caching Middleware
module Rack::Cache
  require 'rack/cache/storage'
  require 'rack/cache/request'
  require 'rack/cache/response'
  require 'rack/cache/context'
  require 'rack/cache/language'

  def self.new(*args, &b)
    Context.new(*args, &b)
  end
end
