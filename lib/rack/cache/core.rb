require 'rack/cache/request'
require 'rack/cache/response'

module Rack::Cache

  # Raised when an attempt is made to transition to an event that can
  # not be transitioned from the current event.
  class IllegalTransition < Exception
  end

  # The core caching engine.
  module Core

    # The request we make downstream
    attr_reader :request

    # The response that will be sent upstream
    attr_reader :response

    # The request as received from upstream
    attr_reader :original_request

    # The response as received from downstream
    attr_reader :original_response

    # A response object retrieved from cache, or nil if no cached
    # response was found.
    attr_reader :object

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

    def request
      @request || @original_request
    end

    def response
      @response || @original_response
    end

    # Determine if the response's Last-Modified date matches the
    # If-Modified-Since value provided in the original request.
    def not_modified?
      response.last_modified_at?(original_request.if_modified_since)
    end

  protected

    # Attach rules to an event.
    def on(event, &block)
      @events[event].unshift block
      (class << self;self;end).send :define_method, event do
        throw :transition, event
      end
      nil
    end

  private

    # Trigger processing of the event specified.
    def trigger(event)
      if (events = @events[event]).any?
        @trace << event
        catch(:transition) do
          events.each { |block| instance_eval(&block) }
          nil
        end
      else
        raise NameError, "No such event: #{event}"
      end
    end

    # Transition from the currently processing event to the event
    # specified.
    def transition(possible, event, *args, &tweek)
      if ! possible.include?(event)
        raise IllegalTransition,
          "No transition to :#{event}"
      end
      event = yield(event) if block_given?
      send "#{event}!", *args
    end

    # Declare the current request as volatile. This is necessary before
    # changes can be made to the request.
    def volatile_request
      @request ||=
        Request.new(original_request.env.dup)
    end

    # Delegate the request to the backend and create the response.
    def fetch_from_backend!
      response = backend.call(request.env)
      @original_response = Response.new(*response)
    end

    # Mark the response as being not modified.
    def not_modified!
      response.status = 304
      response.body = ''
    end

  private

    def receive!
      @original_request = Request.new(@env)
      info "%s %s", @original_request.request_method, @original_request.fullpath
      transition [:pass, :lookup], trigger(:receive)
    end

    def pass!
      fetch_from_backend!
      transition [:pass, :finish, :lookup], trigger(:pass) do |ev|
        ev == :pass ? :finish : ev
      end
    end

    def lookup!
      if tuple = storage.get(original_request.fullpath)
        if (@object = Response.activate(tuple)).fresh?
          transition [:deliver, :pass], trigger(:hit)
        else
          validate!
        end
      else
        transition [:fetch, :pass], trigger(:miss)
      end
    end

    # TODO handle 412 responses
    def validate!
      volatile_request

      # add our cached validators to the backend request
      request.headers['If-Modified-Since'] = object.last_modified
      request.headers['If-None-Match'] = object.etag

      fetch_from_backend!

      if original_response.status == 304
        debug "cached object validated with backend"
        @response = object.dup
        @response.headers.delete('Age')
        %w[Date Expires Cache-Control Etag Last-Modified].each do |name|
          next unless original_response.header?(name)
          @response[name] = original_response[name]
        end
        @response.activate!
      end

      transition [:store, :deliver], trigger(:fetch)
    end

    def fetch!
      volatile_request.
        env.delete('HTTP_IF_MODIFIED_SINCE')
      fetch_from_backend!
      transition [:store, :deliver], trigger(:fetch)
    end

    def store!
      @object = response.dup
      @object.remove_uncacheable_headers!
      transition [:persist, :deliver], trigger(:store) do |event|
        storage.put(original_request.fullpath, @object) if event == :persist
        :deliver
      end
    end

    def deliver!
      @response = response || object
      not_modified! if not_modified?
      transition [:finish], trigger(:deliver)
    end

    def finish!
      response.to_a
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
      @original_request = nil
      @original_response = nil
      @object = nil
    end

    # Process a request. This method is compatible with Rack's #call
    # interface.
    def process_request(env)
      @trace = []
      @env = env
      receive!
    end

    %w[receive pass fetch lookup store hit miss deliver finish persist].each do |method_name|
      method_name = method_name.to_sym
      send(:define_method, method_name) { throw(:transition, method_name) }
   end

  end
end
