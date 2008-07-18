module Rack::Cache

  class Language

    # The request as made to the RCL application and that will be
    # passed downstream when #pass is invoked.
    attr_reader :request

    # The response that will be sent to upstream.
    attr_reader :response

    # The Rack compatible object immediately downstream.
    attr_reader :backend

    # The request that will be sent to the backend.
    attr_reader :backend_request

    # The response that was received from the backend.
    attr_reader :backend_response

    # The response object retrieved from the cache, or nil if no cached
    # response was found.
    attr_reader :object

    alias req request
    alias res response

    alias bereq backend_request
    alias beres backend_response

    def initialize(backend, options={}, &block)
      @backend = backend
      @options = options
      @storage = options[:store] || Storage::Memory.new
      @events = {}
      default!
      instance_eval(&block) if block_given?
    end

    def call(env)
      dup.call!(env)
    end

  private

    def call!(env)
      @env = env
      @request = Rack::Request.new(env)
      @response = nil
      @backend_request = nil
      @backend_response = nil
      @object = nil
      perform :receive
      @response.finish
    end

    def on(event, &block)
      (@events[event.to_sym] ||= []).unshift block
      nil
    end

    def error(code, reason=nil)
      @response = Response.new([], code)
      @env['rcl.error'] = [code, reason]
      throw :perform, :error
    end

    def pass
      throw :perform, :pass
    end

    def lookup
      throw :perform, :lookup
    end

    def deliver
      throw :perform, :deliver
    end

    def hit
      throw :perform, :hit
    end

    def miss
      throw :perform, :miss
    end

    def send_backend_request(backend_request=request)
      fail "backend request already sent" unless @backend_request.nil?
      @backend_request = backend_request
      status, header, body = backend.call(backend_request.env)
      @backend_response = Response.new(body, status, header)
    end

    def perform(event)
      if (events = Array(@events[event])).any?
        next_event =
          catch(:perform) do
            events.each { |block| instance_eval(&block) }
            nil
          end
        perform next_event
      end
    end

    # Default Configuration ================================================

    # The default cache configuration.
    def default!

      on :receive do
        pass unless request_method? 'GET', 'HEAD'
        pass if request.header? 'Expect', 'Authorization', 'Cookie'
        lookup
      end

      on :pass do
        send_backend_request
        @response = backend_response
      end

      on :lookup do
        hit if @object = @cache.get(request.url)
        miss
      end

      # Cache hit - object is the response retrieved from cache.
      on :hit do
        pass unless @object.cacheable?
        validate unless @object.fresh?
        deliver
      end

      # Cache miss - 
      on :miss do
        fetch
      end

      on :revalidate do
        request.env['HTTP_IF_MODIFIED_SINCE'] = object.headers['Last-Modified']
        send_backend_request
      end

      on :fetch do
        error unless response.valid?
        pass if response.header?('Set-Cookie')
        if @response.cacheable?
          insert
        else
          pass
        end
      end

      on :deliver do
        @response = @object
      end

    end

  end

end
