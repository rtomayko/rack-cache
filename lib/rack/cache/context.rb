require 'rack/cache/config'
require 'rack/cache/options'
require 'rack/cache/core'
require 'rack/cache/request'
require 'rack/cache/response'
require 'rack/cache/storage'

module Rack::Cache

  # The context of an individual request.
  #
  #   Rack::Adapter -> Rack::Cache -> RackApplication
  #
  class Context
    include Rack::Cache::Options
    include Rack::Cache::Config
    include Rack::Cache::Core

    # The Rack application object immediately downstream.
    attr_reader :backend

    def initialize(backend, options={}, &block)
      @errors = nil
      @env = nil
      @backend = backend
      initialize_options options
      initialize_core
      initialize_config(&block)
    end

    # The Rack call interface. The receiver acts as a prototype and runs each
    # request in a duplicate object, unless the +rack.run_once+ variable is set
    # in the environment.
    def call(env)
      if env['rack.run_once']
        call! env
      else
        # NOTE we can't use #dup here because we need the methods defined
        # on the object's metaclass to be copied.
        clone.call! env
      end
    end

    alias_method :call!, :process_request
    protected :call!

    # IO-like object that receives log, warning, and error messages;
    # defaults to the rack.errors environment variable.
    def errors
      @errors || (@env && (@errors = @env['rack.errors'])) || STDERR
    end

    # Set the output stream for log messages, warnings, and errors.
    def errors=(ioish)
      fail "stream must respond to :write" if ! ioish.respond_to?(:write)
      @errors = ioish
    end

    # The configured MetaStore instance. Changing the rack-cache.metastore
    # environment variable effects the result of this method immediately.
    def metastore
      uri = options['rack-cache.metastore']
      storage.meta_store[uri]
    end

    # The configured EntityStore instance. Changing the rack-cache.entitystore
    # environment variable effects the result of this method immediately.
    def entitystore
      uri = options['rack-cache.entitystore']
      storage.entity_store[uri]
    end

  protected

    # Write a log message to the errors stream. +level+ is a symbol
    # such as :error, :warn, :info, or :trace.
    def log(level, message=nil, *interpolators)
      errors.write("[cache] #{level}: #{message}\n" % interpolators)
      errors.flush
    end

    def info(*message, &bk)
      log :info, *message, &bk
    end

    def warn(*message, &bk)
      log :warn, *message, &bk
    end

    def trace(*message, &bk)
      return unless verbose?
      log :trace, *message, &bk
    end

    alias_method :debug, :trace

  end

end
