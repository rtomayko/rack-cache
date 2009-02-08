require 'rack/cache/options'
require 'rack/cache/request'
require 'rack/cache/response'
require 'rack/cache/storage'

module Rack::Cache
  # Implements Rack's middleware interface and provides the context for all
  # cache logic, including the core logic engine.
  class Context
    include Rack::Cache::Options

    # The request exactly as received. The object is an instance of
    # Rack::Cache::Request.  This object cannot be modified. If the
    # request requires modification before being delivered to the
    # downstream application, use the #request object.
    attr_reader :original_request

    # The request that will be made downstream on the application. This
    # defaults to the request exactly as received (#original_request). The
    # object is an instance of Rack::Cache::Request.
    attr_reader :request

    # Array of trace Symbols
    attr_reader :trace

    # The Rack application object immediately downstream.
    attr_reader :backend

    def initialize(backend, options={}, &block)
      @errors = nil
      @backend = backend
      @trace = []
      initialize_options options
      instance_eval(&block) if block_given?
    end

    # IO-like object that receives log, warning, and error messages;
    def errors
      (@errors ||= options['rack-cache.errors'] || @env['rack.errors']) ||
        STDERR
    end

    # The configured MetaStore instance. Changing the rack-cache.metastore
    # value effects the result of this method immediately.
    def metastore
      uri = options['rack-cache.metastore']
      storage.resolve_metastore_uri(uri)
    end

    # The configured EntityStore instance. Changing the rack-cache.entitystore
    # value effects the result of this method immediately.
    def entitystore
      uri = options['rack-cache.entitystore']
      storage.resolve_entitystore_uri(uri)
    end

    # The Rack call interface. The receiver acts as a prototype and runs
    # each request in a dup object unless the +rack.run_once+ variable is
    # set in the environment.
    def call(env)
      if env['rack.run_once']
        call! env
      else
        clone.call! env
      end
    end

    # The real Rack call interface. The caching logic is performed within
    # the context of the receiver.
    def call!(env)
      @trace = []
      @env = @default_options.merge(env)
      dispatch
    end

  private
    # Record that an event took place.
    def record(event)
      @trace << event
    end

    # Write a log message to the errors stream. +level+ is a symbol
    # such as :error, :warn, :info, or :trace.
    def log(message=nil, *params)
      errors.write("cache: #{message}\n" % params)
      errors.flush
    end

  private
    # Does the request include authorization or other sensitive information
    # that should cause the response to be considered private by default?
    # Private responses are not stored in the cache.
    def private_request?
      request.header?(*private_headers)
    end

    # Determine if the #response validators (ETag, Last-Modified) matches
    # a conditional value specified in #original_request.
    def not_modified?(response)
      response.etag_matches?(original_request.if_none_match) ||
        response.last_modified_at?(original_request.if_modified_since)
    end

    # Called at the beginning of request processing, after the complete
    # request has been fully received. Its purpose is to decide whether or
    # not to serve the request from cache and will transition to the either
    # the #pass or #lookup states.
    def dispatch
      # Store the request env exactly as we received it. Freeze the env to
      # ensure no changes are made.
      @original_request = Request.new(@env.dup.freeze)

      @env['REQUEST_METHOD'] = 'GET' if @original_request.head?
      @request = Request.new(@env)

      response =
        if @request.method?('GET', 'HEAD') && !@request.header?('Expect')
          lookup
        else
          pass
        end

      # log trace and set X-Rack-Cache tracing header
      trace = @trace.join(', ')
      log trace if verbose?
      response['X-Rack-Cache'] = trace

      # tidy up response a bit
      response.not_modified! if not_modified?(response)
      response.body = [] if @original_request.head?
      response.headers.delete 'X-Status'
      response.to_a
    end

    # Delegate the request to the backend and create the response.
    def forward
      Response.new(*backend.call(request.env))
    end

    # The request is sent to the backend, and the backend's response is sent
    # to the client, but is not entered into the cache.
    def pass
      record :pass
      @request.env['REQUEST_METHOD'] = @original_request.request_method
      forward
    end

    # Try to serve the response from cache. When a matching cache entry is
    # found and is fresh, use it as the response without forwarding any
    # request to the backend. When a matching cache entry is found but is
    # stale, attempt to #validate the entry with the backend using conditional
    # GET. When no matching cache entry is found, trigger #miss processing.
    def lookup
      if request.no_cache?
        record :reload
        return fetch
      end

      entry = metastore.lookup(original_request, entitystore)
      if entry && entry.fresh?
        record :fresh
        return entry
      end

      if entry
        record :stale
        validate(entry)
      else
        record :miss
        fetch
      end
    end

    # Validate that the cache entry is fresh. The original request is used
    # as a template for a conditional GET request with the backend.
    def validate(entry)
      # add our cached validators to the backend request
      request.headers['If-Modified-Since'] = entry.last_modified
      request.headers['If-None-Match'] = entry.etag
      backend_response = forward

      response =
        if backend_response.status == 304
          record :valid
          entry = entry.dup
          entry.headers.delete('Age')
          entry.headers.delete('Date')
          %w[Date Expires Cache-Control Etag Last-Modified].each do |name|
            next unless value = backend_response.headers[name]
            entry[name] = value
          end
          entry.activate!
          entry
        else
          record :invalid
          backend_response
        end
      store(response) if response.cacheable?

      response
    end

    # The cache missed or a reload is required. Forward the request to the
    # backend and determine whether the response should be stored.
    def fetch
      request.env.delete('HTTP_IF_MODIFIED_SINCE')
      request.env.delete('HTTP_IF_NONE_MATCH')
      response = forward

      # mark the response as explicitly private if any of the private
      # request headers are present and the response was not explicitly
      # declared public.
      if private_request? && !response.public?
        response.private = true
      elsif default_ttl > 0 && response.ttl.nil? && !response.must_revalidate?
        # assign a default TTL for the cache entry if none was specified in
        # the response; the must-revalidate cache control directive disables
        # default ttl assigment.
        response.ttl = default_ttl
      end
      store(response) if response.cacheable?

      response
    end

    # Write the response to the cache.
    def store(response)
      record :store
      metastore.store(original_request, response, entitystore)
      nil
    end
  end
end
