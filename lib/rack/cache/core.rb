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
  module Core

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

    # Has the given event been performed at any time during the
    # request life-cycle? Useful for testing.
    def performed?(event)
      @triggered.include?(event)
    end

  private
    # Event handlers.
    attr_reader :events

  public
    # Attach custom logic to one or more events.
    def on(*events, &block)
      events.each { |event| @events[event].unshift(block) }
      nil
    end

  private
    # Transitioning statements

    def pass!      ; throw(:transition, [:pass])    ; end
    def lookup!    ; throw(:transition, [:lookup])  ; end
    def store!     ; throw(:transition, [:store])   ; end
    def fetch!     ; throw(:transition, [:fetch])   ; end
    def persist!   ; throw(:transition, [:persist]) ; end
    def deliver!   ; throw(:transition, [:deliver]) ; end
    def finish!    ; throw(:transition, [:finish])  ; end

    def error!(code=500, headers={}, body=nil)
      throw(:transition, [:error, code, headers, body])
    end

  private
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

  private
    def perform_receive
      @original_request = Request.new(@env.dup.freeze)
      @request = Request.new(@env)
      info "%s %s", @original_request.request_method, @original_request.fullpath
      transition(from=:receive, to=[:pass, :lookup, :error])
    end

    def perform_pass
      trace 'passing'
      fetch_from_backend
      transition(from=:pass, to=[:pass, :finish, :error]) do |event|
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
      if @entry = metastore.lookup(original_request, entitystore)
        if @entry.fresh?
          trace 'cache hit (ttl: %ds)', @entry.ttl
          transition(from=:hit, to=[:deliver, :pass, :error]) do |event|
            @response = @entry if event == :deliver
            event
          end
        else
          trace 'cache stale (ttl: %ds), validating...', @entry.ttl
          perform_validate
        end
      else
        trace 'cache miss'
        transition(from=:miss, to=[:fetch, :pass, :error])
      end
    end

    def perform_validate
      # add our cached validators to the backend request
      request.headers['If-Modified-Since'] = entry.last_modified
      request.headers['If-None-Match'] = entry.etag
      fetch_from_backend

      if original_response.status == 304
        trace "cache entry valid"
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
        trace "cache entry invalid"
        @entry = nil
      end
      transition(from=:fetch, to=[:store, :deliver, :error])
    end

    def perform_fetch
      trace "fetching response from backend"
      request.env.delete('HTTP_IF_MODIFIED_SINCE')
      request.env.delete('HTTP_IF_NONE_MATCH')
      fetch_from_backend
      transition(from=:fetch, to=[:store, :deliver, :error])
    end

    def perform_store
      @entry = @response
      transition(from=:store, to=[:persist, :deliver, :error]) do |event|
        if event == :persist
          trace "writing response to cache"
          metastore.store(original_request, @entry, entitystore)
          @response = @entry
          :deliver
        else
          event
        end
      end
    end

    def perform_deliver
      trace "delivering response ..."
      response.not_modified! if not_modified?
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

    # Trigger processing of the event specified and return an array containing
    # the name of the next transition and any arguments provided to the
    # transitioning statement.
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

      # initialize some instance variables; we won't use them until we dup to
      # process a request.
      @request = nil
      @response = nil
      @original_request = nil
      @original_response = nil
      @entry = nil
    end

    # Process a request. This method is compatible with Rack's #call
    # interface.
    def process_request(env)
      @triggered = []
      @env = @default_options.merge(env)
      perform_receive
    end
  end
end
