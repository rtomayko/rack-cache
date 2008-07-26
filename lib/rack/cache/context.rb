require 'rack/cache/config'
require 'rack/cache/options'

module Rack::Cache

  # The context of an individual request.
  #
  #   Rack::Adapter -> Rack::Cache -> RackApplication
  #
  class Context
    include Rack::Cache::Options
    include Rack::Cache::Config

    # The Rack compatible object immediately downstream.
    attr_reader :backend

    # The request as made to the RCL application.
    attr_reader :request

    # The response that will be sent upstream.
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
      initialize_options(options)
      initialize_config
      import 'rack/cache/config/default'
      instance_eval(&b) if block_given?
      # initialize some instance variables here but we won't use
      # them until we dup to process a request.
      @request = nil
      @response = nil
      @backend_request = nil
      @backend_response = nil
      @object = nil
    end

    # The Rack call interface. Note that the receiver acts as a
    # prototype and runs each request in a duplicate object,
    # unless the +rack.run_once+ variable is set in the environment.
    def call(env)
      if env['rack.run_once']
        call! env
      else
        dup.send :call!, env
      end
    end

    # The actual call interface.
    def call!(env)
      @env = env
      @request = Request.new(env)
      @trace = []
      debug("%s %s", @request.request_method, @request.fullpath)
      catch(:finish) {
        perform :receive
        fail 'not finished'
      }
    end

  protected

    def copy_request!
      @backend_request = Request.new(@request.env.dup)
    end

  private

    # TODO there has to be a better way

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
