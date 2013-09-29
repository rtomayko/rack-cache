module Rack::Cache
  class Railtie < Rails::Railtie
    initializer "rack-cache.install_middleware" do |app|
      params = app.config.action_dispatch.rack_cache
      next unless params

      # If this require succeeds, then we are running with an older version of
      # Rails that has its own configuration process for rack-cache, and we
      # should not interfere with it.
      begin
        require "action_dispatch/http/rack_cache"
        next
      rescue LoadError; end

      if params == true
        params = {
          :metastore => "rails:/",
          :entitystore => "rails:/",
          :verbose => false
        }
      end

      # We want to position Rack::Cache downstream of a few of these components
      # of the default Rails middleware stack.
      if app.config.serve_static_assets
        upstream = ::ActionDispatch::Static
      elsif app.config.action_dispatch.x_sendfile_header
        upstream = ::Rack::Sendfile
      elsif app.config.force_ssl
        upstream = ::ActionDispatch::SSL
      end

      if upstream
        app.middleware.insert_after(upstream, Rack::Cache, params)
      else
        app.middleware.insert(0, Rack::Cache, params)
      end

      Rack::Cache::MetaStore::RAILS = Rack::Cache::MetaStore::RailsStore
      Rack::Cache::EntityStore::RAILS = Rack::Cache::EntityStore::RailsStore
    end
  end
end
