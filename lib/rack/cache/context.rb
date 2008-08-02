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

    # TODO extract into log module
    attr_writer :errors

    def errors
      @errors ||=
        ((@env && @env['rack.errors']) || STDERR)
    end

    def nowhere
      @null ||= File.open('/dev/null', 'w')
    end

    LOG_LEVELS = {
      :trace    => [ 'TRACE', false ],
      :info     => [ 'INFO ', true ],
      :user     => [ 'USER ', true ],
      :warn     => [ 'WARN ', true ],
      :error    => [ 'ERROR', true ]
    }

    def verbose(*levels)
      levels.each do |level|
        fail "Unknown log level: #{level}" unless LOG_LEVELS.key?(level)
        LOG_LEVELS[level][-1] = true
      end
    end

    def quiet(*levels)
      levels.each { |level| LOG_LEVELS[level][-1] = false }
    end

    def log(level, message=nil, *interpolators, &bk)
      label, enabled = LOG_LEVELS[level]
      return unless enabled
      if block_given?
        args.unshift message unless message.nil?
        message = yield
      end
      errors.write "[RCL] [#{label}] #{message}\n" % interpolators
      errors.flush
    end

    def trace(*message, &bk)
      log :trace, *message, &bk
    end

    def info(*message, &bk)
      log :info, *message, &bk
    end

    def warn(*message, &bk)
      log :warn, *message, &bk
    end

    def error(*message, &bk)
      log :error, *message, &bk
    end

    alias_method :debug, :trace

  end

end
