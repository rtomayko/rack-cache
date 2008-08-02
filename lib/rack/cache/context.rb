require 'rack/cache/config'
require 'rack/cache/options'
require 'rack/cache/core'
require 'rack/cache/request'
require 'rack/cache/response'

module Rack::Cache

  # The context of an individual request.
  #
  #   Rack::Adapter -> Rack::Cache -> RackApplication
  #
  class Context
    include Rack::Cache::Options
    include Rack::Cache::Config
    include Rack::Cache::Core

    # The Rack compatible object immediately downstream.
    attr_reader :backend

    def initialize(backend, options={}, &b)
      @backend = backend
      initialize_options options
      initialize_core
      initialize_config &b
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

    alias_method :call!, :process_request

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
