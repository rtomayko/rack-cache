require 'rack/cache/request'
require 'rack/cache/response'

module Rack::Cache

  # The 
  #
  #   Rack::Adapter -> Rack::Cache -> RackApplication
  #
  module Core

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

    # Event handlers
    attr_reader :events

    # Array of event names that have been executed.
    attr_reader :trace

    # Has the event been performed at any time during the request
    # life-cycle? Most useful for testing.
    def performed?(event)
      @trace.include?(event)
    end

    # Are we currently performing the event specified?
    def performing?(event)
      @trace.last == event
    end

  protected

    # Attach rules to an event.
    def on(event, &block)
      @events[event].unshift block
      nil
    end

    # Bootstrap or transition the machine to the event specified.
    def perform(event)
      if @trace.any?
        transition event
      else
        bootstrap event
      end
    end

    # Bootstraps the configuration machine at the event specified.
    def bootstrap(event)
      while event
        if (events = @events[event]).any?
          @trace << event
          event =
            catch(:transition) do
              events.each { |block| instance_eval(&block) }
              nil
            end
        else
          fail "unknown event: #{event}"
        end
      end
    end

    # Transition from the currently processing event to the event
    # specified.
    def transition(event)
      throw :transition, event.to_sym
    end

  private

    # Setup the core template. The object's state after execution
    # of this method will be duped and used for individual request.
    def initialize_core
      @events = Hash.new { |h,k| h[k.to_sym] = [] }
      @trace = []
      # initialize some instance variables; we won't use
      # them until we dup to process a request.
      @request = nil
      @response = nil
      @backend_request = nil
      @backend_response = nil
      @object = nil
    end

    # Process a request. This method is compatible with Rack's #call
    # interface.
    def process_request(env)
      @env = env
      @request = Request.new(env)
      @trace = []
      debug "%s %s", @request.request_method, @request.fullpath
      catch(:finish) {
        perform :receive
        fail 'not finished'
      }
    end

    def copy_request!
      @backend_request = Request.new(@request.env.dup)
    end

  public

    # We respond to messages with event names by performing the event.
    def respond_to?(symbol, include_private=false)
      @events.key?(symbol) || super
    end

  private

    # Perform events when messages are received that match event names.
    def method_missing(symbol, *args, &b)
      if args.empty? && b.nil? && @events.key?(symbol)
        perform symbol
      else
        super
      end
    end

  end
end
