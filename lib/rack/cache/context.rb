require 'rack/cache/config'

module Rack::Cache

  # The context of an individual request.
  #
  #   Rack::Adapter -> Rack::Cache -> RackApplication
  # 
  class Context
    include Rack::Cache::Config

    # The Rack compatible object immediately downstream.
    attr_reader :backend

    # Where cached objects are stored (Cache::Storage)
    attr_reader :storage

    # The request as made to the RCL application.
    attr_reader :request

    # The response that will be sent to upstream.
    attr_reader :response

    # The response object retrieved from the cache, or nil if no cached
    # response was found.
    attr_reader :object

    # The request that will be sent to the backend.
    attr_reader :backend_request

    # The response that was received from the backend.
    attr_reader :backend_response

    alias req request
    alias res response

    alias bereq backend_request
    alias beres backend_response

    def initialize(backend, options={}, &b)
      @backend = backend
      @options = options
      @storage = options[:store] || Storage::Memory.new
      super()
      import 'rack/cache/config/default'
      instance_eval(&block) if block_given?
      @request = nil
      @response = nil
      @backend_request = nil
      @backend_response = nil
      @object = nil
    end

    # The Rack call interface.
    def call(env)
      # receiver acts as a prototype and runs each request in a duplicate
      # object unless the rack.run_once variable is set.
      if env['rack.run_once']
        call! env
      else
        dup.send :call!, env
      end
    end

    def call!(env)
      @env = env
      @request = Request.new(env)
      @backend_request = Request.new(env.dup)
      @trace = []
      debug("%s %s", @request.request_method, @request.fullpath)
      catch(:finish) {
        perform :receive
        fail 'not finished'
      }
    end

  private

    def debug_stderr(message, *args)
      STDERR.printf "[RCL] #{message}\n", *args
    end

    def debug_error_stream(message, *args)
      @env['rack.errors'] << "[RCL] #{message}\n" % args
    end

    def debug_discard(message, *args)
    end

    alias_method :debug, :debug_error_stream

  end

end
