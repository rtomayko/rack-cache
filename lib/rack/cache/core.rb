require 'rack/cache/request'
require 'rack/cache/response'

module Rack::Cache

  # Raised when an attempt is made to transition to an event that can
  # not be transitioned from the current event.
  class IllegalTransition < Exception
  end

  # The core logic engine and state machine. When a request is received,
  # the engine begins transitioning from state to state based on the
  # advice given by events. Each transition performs some piece of core
  # logic, calls out to an event handler, and then kicks off the next
  # transition.
  #
  # Five object of interest are made available during execution:
  #
  # * #original_request - The request as originally received. This object
  #   is not modified.
  # * #request - The request that may eventually be sent downstream in
  #   case of pass or miss. This object defaults to the #original_request
  #   but may be modified or replaced entirely.
  # * #original_response - The response exactly as specified by the
  #   downstream application. This is nil on cache hit.
  # * #object - The response loaded from cache or stored to cache. This
  #   object becomes #response if the cached response is valid.
  # * #response - The response that will be delivered upstream after
  #   processing is complete. This object may be modified as necessary.
  #
  # These objects can be accessed and modified from within event handlers
  # to perform various types of request/response manipulation.
  module Core

    # The request as received from upstream. This object should never
    # be modified. If the request requires modification before being
    # sent to the downstream application, use the #request object after
    # calling #volatile_request. The object is an instance of the
    # Rack::Cache::Request class, which includes many utility methods
    # for inspecting the state of the request.
    attr_reader :original_request

    # The response as received from the downstream application. This
    # object should never be modified. Use the #response object to access
    # the response to be sent back upstream. The object is an instance
    # of the Rack::Cache::Response class, which include many utility
    # methods for inspecting the state of the response.
    attr_reader :original_response

    # A response object retrieved from cache, or nil if no cached
    # response was found. The object is an instance of the
    # Rack::Cache::Response class.
    attr_reader :object

    # The request that will be made downstream on the application. This
    # defaults to the request exactly as received (#original_request). The
    # object is an instance of the Rack::Cache::Request class, which includes
    # utility methods for inspecting and modifying various aspects of the
    # HTTP request.
    #
    # The #volatile_request method ensures that a separate clone of the original
    # request is created and made available here for situations where the
    # original requests needs to be modified.
    def request
      @request || @original_request
    end

    # The response that will be sent upstream. Defaults to the response
    # received from the downstream application (#original_response) but
    # is set to the cached #object when valid. In any case, the object
    # is an instance of the Rack::Cache::Response class, which includes a
    # variety of utility methods for inspecting and modifying the HTTP
    # response.
    def response
      @response || @original_response
    end

    # Event handlers.
    attr_reader :events

    # Has the given event been performed at any time during the
    # request life-cycle? Useful for testing.
    def performed?(event)
      @triggered.include?(event)
    end

  protected
    # Declare the current request as volatile. This is necessary before
    # changes can be made to the request.
    def volatile_request
      @request ||= Request.new(original_request.env.dup)
    end

    # Attach rules to an event.
    def on(*events, &block)
      events.each do |event|
        @events[event].unshift block if block_given?
        next if respond_to? "#{event}!"
        meta_def("#{event}!") { |*args| throw(:transition, [event, *args]) }
        nil
      end
    end

    # Determine if the response's Last-Modified date matches the
    # If-Modified-Since value provided in the original request.
    def not_modified?
      response.last_modified_at?(original_request.if_modified_since)
    end

    # Delegate the request to the backend and create the response.
    def fetch_from_backend
      response = backend.call(request.env)
      @original_response = Response.new(*response)
    end

  private
    def perform_receive
      @original_request = Request.new(@env)
      info "%s %s", @original_request.request_method, @original_request.fullpath
      transition(from=:receive, to=[:pass, :lookup, :error])
    end

    def perform_pass
      trace 'passing'
      fetch_from_backend
      transition(from=:pass, to=[:pass, :finish, :lookup, :error]) do |event|
        if event == :pass
          :finish
        else
          event
        end
      end
    end

    def perform_error(code=500, headers={}, body=nil)
      body, headers = headers, {} unless headers.is_a?(Hash)
      headers = {} if headers.nil?
      body = [] if body.nil? || body == ''
      @response = Rack::Cache::Response.new(code, headers, body)
      transition(from=:error, to=[:finish])
    end

    def perform_lookup
      if @object = meta_store.lookup(original_request, entity_store)
        if @object.fresh?
          trace 'cache hit (ttl: %ds)', @object.ttl
          transition(from=:hit, to=[:deliver, :pass, :error])
        else
          trace 'cache stale (ttl: %ds), validating...', @object.ttl
          perform_validate
        end
      else
        trace 'cache miss'
        transition(from=:miss, to=[:fetch, :pass, :error])
      end
    end

    def perform_validate
      volatile_request

      # add our cached validators to the backend request
      request.headers['If-Modified-Since'] = object.last_modified
      request.headers['If-None-Match'] = object.etag
      fetch_from_backend

      if original_response.status == 304
        trace "cached object valid"
        @response = object.dup
        @response.headers.delete('Age')
        @response.headers['X-Origin-Status'] = '304'
        %w[Date Expires Cache-Control Etag Last-Modified].each do |name|
          next unless value = original_response.headers[name]
          @response[name] = value
        end
        @response.activate!
      else
        trace "cached object invalid"
        @object = nil
      end
      transition(from=:fetch, to=[:store, :deliver, :error])
    end

    def perform_fetch
      trace "fetching response from backend"
      volatile_request
      request.env.delete('HTTP_IF_MODIFIED_SINCE')
      request.env.delete('HTTP_IF_NONE_MATCH')
      fetch_from_backend
      transition(from=:fetch, to=[:store, :deliver, :error])
    end

    def perform_store
      @object = response
      transition(from=:store, to=[:persist, :deliver, :error]) do |event|
        if event == :persist
          trace "writing response to cache"
          meta_store.store(original_request, @object, entity_store)
          @response = @object
          :deliver
        else
          event
        end
      end
    end

    def perform_deliver
      trace "delivering response ..."
      @response = response || object
      if not_modified?
        response.status = 304
        response.body = []
      end
      transition(from=:deliver, to=[:finish, :error])
    end

    def perform_finish
      response.to_a
    end

  private
    # Transition from the currently processing event to another event
    # after triggering event handlers.
    def transition(from, to)
      ev, *args = trigger(from)
      raise IllegalTransition, "No transition to :#{ev}" unless to.include?(ev)
      ev = yield ev if block_given?
      send "perform_#{ev}", *args
    end

    # Trigger processing of the event specified.
    def trigger(event)
      if @events.include? event
        @triggered << event
        catch(:transition) do
          @events[event].each { |block| instance_eval(&block) }
          nil
        end
      else
        raise NameError, "No such event: #{event}"
      end
    end

  private
    # Setup the core prototype. The object's state after execution
    # of this method will be duped and used for individual request.
    def initialize_core
      @triggered = []
      @events = Hash.new { |h,k| h[k.to_sym] = [] }
      on :receive, :pass, :miss, :hit, :fetch, :lookup, :store,
        :persist, :deliver, :finish, :error

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
      @triggered = []
      @env = env
      perform_receive
    end

  public
    def metaclass #:nodoc
      (class << self ; self ; end)
    end
    def meta_def(name, *args, &blk) #:nodoc
      metaclass.send :define_method, name, *args, &blk
    end

  end
end
