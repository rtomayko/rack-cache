require 'rack/cache/options'
require 'rack/cache/request'
require 'rack/cache/response'
require 'rack/cache/storage'

module Rack::Cache
  # Implements Rack's middleware interface and provides the context for all
  # cache logic.

  # The core logic engine and state machine. When a request is received,
  # the engine begins transitioning from state to state based on the
  # advice given by events. Each transition performs some piece of core
  # logic, calls out to an event handler, and then kicks off the next
  # transition.
  #
  # Five objects of interest are made available during execution:
  #
  # * +original_request+ - The request as originally received. This object
  #   is never modified.
  # * +request+ - The request that may eventually be sent downstream in
  #   case of pass or miss. This object defaults to the +original_request+
  #   but may be modified or replaced entirely.
  # * +original_response+ - The response exactly as specified by the
  #   downstream application; +nil+ on cache hit.
  # * +entry+ - The response loaded from cache or stored to cache. This
  #   object becomes +response+ if the cached response is valid.
  # * +response+ - The response that will be delivered upstream after
  #   processing is complete. This object may be modified as necessary.
  #
  # These objects can be accessed and modified from within event handlers
  # to perform various types of request/response manipulation.
  class Context
    include Rack::Cache::Options

    # The request exactly as received. The object is an instance of the
    # Rack::Cache::Request class, which includes many utility methods for
    # inspecting the state of the request.
    #
    # This object cannot be modified. If the request requires modification
    # before being delivered to the downstream application, use the
    # #request object.
    attr_reader :original_request

    # The response exactly as received from the downstream application. The
    # object is an instance of the Rack::Cache::Response class, which includes
    # utility methods for inspecting the state of the response.
    #
    # The original response should not be modified. Use the #response object to
    # access the response to be sent back upstream.
    attr_reader :original_response

    # A response object retrieved from cache, or the response that is to be
    # saved to cache, or nil if no cached response was found. The object is
    # an instance of the Rack::Cache::Response class.
    attr_reader :entry

    # The request that will be made downstream on the application. This
    # defaults to the request exactly as received (#original_request). The
    # object is an instance of the Rack::Cache::Request class, which includes
    # utility methods for inspecting and modifying various aspects of the
    # HTTP request.
    attr_reader :request

    # The response that will be sent upstream. Defaults to the response
    # received from the downstream application (#original_response) but
    # is set to the cached #entry when valid. In any case, the object
    # is an instance of the Rack::Cache::Response class, which includes a
    # variety of utility methods for inspecting and modifying the HTTP
    # response.
    attr_reader :response

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
    # environment variable effects the result of this method immediately.
    def metastore
      uri = options['rack-cache.metastore']
      storage.resolve_metastore_uri(uri)
    end

    # The configured EntityStore instance. Changing the rack-cache.entitystore
    # environment variable effects the result of this method immediately.
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
    def log(level, message=nil, *params)
      errors.write("[cache] #{level}: #{message}\n" % params)
      errors.flush
    end

    def warn(*message, &bk)
      log :warn, *message, &bk
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
    def not_modified?
      response.etag_matches?(original_request.if_none_match) ||
        response.last_modified_at?(original_request.if_modified_since)
    end

    # Delegate the request to the backend and create the response.
    def fetch_from_backend
      status, headers, body = backend.call(request.env)
      response = Response.new(status, headers, body)
      @response = response.dup
      @original_response = response.freeze
    end

    def dispatch
      # Store the request env exactly as we received it. Freeze the env to
      # ensure no changes are made.
      @original_request = Request.new(@env.dup.freeze)

      @env['REQUEST_METHOD'] = 'GET' if @original_request.head?
      @request = Request.new(@env)

      if !request.method?('GET', 'HEAD') || request.header?('Expect')
        pass
      else
        lookup
      end

      response.not_modified! if not_modified?
      response.body = [] if @original_request.head?
      response.headers.delete 'X-Status'
      response.to_a
    end

    def pass
      record :pass
      request.env['REQUEST_METHOD'] = @original_request.request_method
      fetch_from_backend
    end

    def lookup
      if @entry = metastore.lookup(original_request, entitystore)
        if @entry.fresh?
          record :fresh
          @response = @entry
        else
          validate
        end
      else
        miss
      end
    end

    def validate
      record :stale

      # add our cached validators to the backend request
      request.headers['If-Modified-Since'] = entry.last_modified
      request.headers['If-None-Match'] = entry.etag
      fetch_from_backend

      if original_response.status == 304
        record :valid
        @response = entry.dup
        @response.headers.delete('Age')
        @response.headers.delete('Date')
        @response.headers['X-Origin-Status'] = '304'
        %w[Date Expires Cache-Control Etag Last-Modified].each do |name|
          next unless value = original_response.headers[name]
          @response[name] = value
        end
        @response.activate!
      else
        record :invalid
        @entry = nil
      end

      store
    end

    def miss
      record :miss

      request.env.delete('HTTP_IF_MODIFIED_SINCE')
      request.env.delete('HTTP_IF_NONE_MATCH')
      fetch_from_backend

      # mark the response as explicitly private if any of the private
      # request headers are present and the response was not explicitly
      # declared public.
      if private_request? && !@response.public?
        @response.private = true
      else
        # assign a default TTL for the cache entry if none was specified in
        # the response; the must-revalidate cache control directive disables
        # default ttl assigment.
        if default_ttl > 0 && @response.ttl.nil? && !@response.must_revalidate?
          @response.ttl = default_ttl
        end
      end

      store
    end

    def store
      return unless response.cacheable?

      record :store
      warn 'forced to store response marked as private.' if @response.private?

      @entry = @response
      metastore.store(original_request, @entry, entitystore)
    end
  end
end
