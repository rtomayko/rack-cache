module Rack::Cache

  module Cacheable

    # The current time; guaranteed to be the same value on repeated
    # calls.
    def now
      @now ||= Time.now
    end

    # The date of the response. If no explicit Date header is present,
    # the current time is 
    def date
      @date ||= 
        if date = headers['Date']
          Time.httpdate(date)
        else
          headers['Date'] = now.httpdate
          now
        end
    end

    def age
      @age ||= now - date
    end

    # The response's time to live, in seconds.
    def ttl
      max_age - age
    end

    def ttl=(value)
      @max_age = age + value
    end

    def fresh?
      ttl > 0
    end

    def stale?
      ttl <= 0
    end

    def valid?
      status < 500
    end

    def cache_control
      @cache_control ||= 
        (headers['Cache-Control'] || '').split(/\s*,\s*/).inject({}) do |hash,token|
          name, value = token.split(/\s*=\s*/, 2)
          hash[name] = value unless name.empty?
          hash
        end
    end

    def expires_at
      @expires_at ||=
        if time = headers['Expires']
          Time.httpdate(time)
        else
          date
        end
    end

    def max_age
      @max_age ||=
        if value = cache_control['max-age']
          value.to_i
        else
          expires_at - date
        end
    end

    def cacheable?
      valid? &&
      fresh? &&
      [200, 203, 300, 301, 302, 404, 410].include?(status) &&
      ! cache_control.include?('no-store')
    end

  end

  class Response < Rack::Response
    include Cacheable
  end

  class MockResponse < Rack::MockResponse
    include Cacheable
  end

end
