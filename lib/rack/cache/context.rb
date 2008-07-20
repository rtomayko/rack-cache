module Rack::Cache

  # The context of an individual request.
  #
  #   Rack::Adapter -> Rack::Cache -> RackApplication
  # 
  class Context

    # The Rack compatible object immediately downstream.
    attr_reader :backend

    # Where cached objects are stored (Cache::Storage)
    attr_reader :storage

    def initialize(backend, options={}, &b)
      @backend = backend
      @options = options
      @storage = options[:store] || Storage::Memory.new
      @events = Hash.new { |h,k| h[k.to_sym] = [] }
      default!
      instance_eval(&block) if block_given?
      @request = nil
      @response = nil
      @backend_request = nil
      @backend_response = nil
      @object = nil
    end

    # Loads the default configuration
    def default!
      file = File.join(File.dirname(__FILE__), 'default.rb')
      source = File.read(file)
      eval source, nil, file
    end

    private :default!

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

    # Attach rules to an event.
    def on(event, &block)
      @events[event].unshift block
      nil
    end

    # Immediately halt processing of current event and move to the
    # event specified.
    def perform(event)
      @trace << event
      if (events = @events[event]).any?
        debug 'perform %p', event
        next_event =
          catch(:perform) do
            events.each { |block| instance_eval(&block) }
            nil
          end
        perform next_event
      end
    end

    # Has the event been performed at any time during the request
    # life-cycle? Most useful for testing.
    def performed?(event)
      @trace.include?(event)
    end

  private

    # Invoke events.
    def method_missing(name, *args, &b)
      if args.empty? && b.nil? && @events.key?(name.to_sym)
        perform name.to_sym
      else
        super
      end
    end

    def debug_stderr(message, *args)
      STDERR.printf "[RCL] #{message}\n", *args
    end

    def debug_discard(message, *args)
    end

    alias_method :debug, :debug_discard

  end

end
