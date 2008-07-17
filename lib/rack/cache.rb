require 'fileutils'
require 'time'
require 'rack'


# Rack Caching Middleware
module Rack::Cache
  require 'rack/cache/request'
  require 'rack/cache/response'
  require 'rack/cache/response'
  require 'rack/cache/language'
  require 'rack/cache/storage'
end
