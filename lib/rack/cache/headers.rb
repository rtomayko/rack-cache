require 'set'
require 'rack/utils/environment_headers'

module Rack::Cache

  module Headers

    # Determine if any of the header names exist:
    #   if header?('Authorization', 'Cookie')
    #     ...
    #   end
    def header?(*names)
      names.any? { |name| headers.include?(name) }
    end

    # A Hash of name=value pairs that correspond to the Cache-Control
    # header. Valueless parameters (e.g., must-revalidate, no-store)
    # have a Hash value of true. This method always returns a Hash,
    # empty if no Cache-Control header is present.
    def cache_control
      @cache_control ||=
        (headers['Cache-Control'] || '').split(/\s*,\s*/).inject({}) do |hash,token|
          name, value = token.split(/\s*=\s*/, 2)
          hash[name.downcase] = (value || true) unless name.empty?
          hash
        end.freeze
    end

    # Set the Cache-Control header to the values specified. This method
    # accepts a Hash. See #cache_control for expected structure.
    def cache_control=(hash)
      value =
        hash.collect do |key,value|
          next nil unless value
          next key if value == true
          "#{key}=#{value}"
        end.compact.join(', ')
      @cache_control = nil
      if value.empty?
        headers.delete('Cache-Control')
      else
        headers['Cache-Control'] = value
      end
    end

    def etag
      headers['Etag']
    end

  end


  # Use methods for accessing HTTP request headers.
  module RequestHeaders
    include Rack::Cache::Headers

    # A Hash-like object providing access to HTTP headers.
    def headers
      @headers ||= Rack::Utils::EnvironmentHeaders.new(env)
    end

    alias :header :headers

    def if_modified_since
      headers['If-Modified-Since']
    end

  end


  # Useful methods for accessing HTTP response headers.
  module ResponseHeaders
    include Rack::Cache::Headers

    # Set of HTTP response codes of messages that can be cached, per
    # RFC 2616.
    CACHEABLE_RESPONSE_CODES = Set.new([200, 203, 300, 301, 302, 404, 410])

    # Determine if the response is worthwhile to a cache under any
    # circumstance. An object that is cacheable may not necessary be
    # served from cache without first validating the response with the
    # origin.
    #
    # An object that includes no freshness lifetime (Expires, max-age) and
    # that does not include a validator (Last-Modified, Etag) serves no
    # purpose in a cache that only serves fresh or valid objects.
    def cacheable?
      return false unless CACHEABLE_RESPONSE_CODES.include?(status)
      return false if no_store?
      validateable? || fresh?
    end

    # The response includes specific information about its freshness.
    # True when a +Cache-Control+ header with +max-age+ value
    # is present or when the +Expires+ header is set.
    def freshness_information?
      header?('Expires') || cache_control['max-age']
    end

    # Determine if the response includes headers that can be used
    # to validate the response with the origin server using a
    # conditional request.
    #--
    # TODO Support ETags
    def validateable?
      header?('Last-Modified') # || header?('ETags')
    end

    # Indicates that the response should not be served from cache without first
    # revalidating with the origin server. Note that this does not necessary
    # imply that a caching agent ought not store the response in its cache.
    def no_cache?
      cache_control['no-cache']
    end

    # Indicates that the response should not be stored under any
    # circumstances.
    def no_store?
      cache_control['no-store']
    end

    def now
      @now ||= Time.now
    end

    # The date, as specified by the Date header. When no Date header
    # is present, set the Date header to Time.now and return.
    def date
      @date ||=
        if date = headers['Date']
          Time.httpdate(date)
        else
          headers['Date'] = now.httpdate unless headers.frozen?
          now
        end
    end

    # The age of the response.
    def age
      [(now - date).to_i, 0].max
    end

    # The number of seconds after the time specified in the response's Date
    # header when the the response should no longer be considered fresh. First
    # check for a Cache-Control max-age value, and fall back on an expires
    # header; return nil when no maximum age can be established.
    def max_age
      if age = cache_control['max-age']
        age.to_i
      elsif headers['Expires']
        Time.httpdate(headers['Expires']) - date
      end
    end

    # Set the age at which the response should no longer be considered fresh.
    # Uses the Cache-Control max-age value.
    def max_age=(value)
      self.cache_control = cache_control.merge('max-age' => value.to_s)
    end

    # The expiration Time of the response as specified by the Expires header,
    # or the 
    # nil when no Expires header is present.
    def expires_at
      if age = cache_control['max-age']
        date + age.to_i
      else
        (time = headers['Expires']) && Time.httpdate(time)
      end
    end

    # The response's time-to-live, in seconds.
    def ttl
      max_age - age if max_age
    end

    # Set the response's time-to-live to the specified number of seconds.
    # The receiver must respond to the #max_age= message.
    def ttl=(seconds)
      self.max_age = age + seconds
    end

    # Determine if the response is "fresh" in the sense that it can be
    # used without first validating with the origin.
    def fresh?
      ttl > 0
    end

    # Determine if the response is "stale" in the sense that it must be
    # validated with the origin before use.
    def stale?
      ttl <= 0
    end

    # The String value of the Last-Modified header exactly as it appears
    # in the response (i.e., no date parsing / conversion is performed).
    def last_modified
      headers['Last-Modified']
    end

    # Determine if the response was last modified at the time provided.
    # time_value is the exact string provided in an origin response's
    # Last-Modified header.
    def last_modified_at?(time_value)
      time_value && last_modified == time_value
    end

    # The literal value of the Vary header, or nil when no Vary header is
    # present.
    def vary
      headers['Vary']
    end

    # Does the response include a Vary header?
    def vary?
      ! vary.nil?
    end

    # Determine whether the two environments vary based on the fields
    # specified in the receiver's Vary header.
    def requests_vary?(env1, env2)
      case vary
      when nil, ''
        false
      when '*'
        true
      else
        vary.split(/\s+/).any? do |header_name|
          key = "HTTP_#{header_name.upcase.tr('-', '_')}"
          env1[key] != env2[key]
        end
      end
    end

  end

end
