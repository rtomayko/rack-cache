require 'set'
require 'rack/utils/environment_headers'

module Rack::Cache
  # Generic HTTP header helper methods. Provides access to headers that can be
  # included in requests and responses. This can be mixed into any object that
  # responds to #headers by returning a Hash.

  module Headers
    # Determine if any of the header names exist:
    #   if header?('Authorization', 'Cookie')
    #     ...
    #   end
    def header?(*names)
      names.any? { |name| headers.include?(name) }
    end

    # A Hash of name=value pairs that correspond to the Cache-Control header.
    # Valueless parameters (e.g., must-revalidate, no-store) have a Hash value
    # of true. This method always returns a Hash, empty if no Cache-Control
    # header is present.
    def cache_control
      @cache_control ||=
        (headers['Cache-Control'] || '').split(/\s*,\s*/).inject({}) {|hash,token|
          name, value = token.split(/\s*=\s*/, 2)
          hash[name.downcase] = (value || true) unless name.empty?
          hash
        }.freeze
    end

    # Set the Cache-Control header to the values specified by the Hash. See
    # the #cache_control method for information on expected Hash structure.
    def cache_control=(hash)
      value =
        hash.collect { |key,value|
          next nil unless value
          next key if value == true
          "#{key}=#{value}"
        }.compact.join(', ')
      if value.empty?
        headers.delete('Cache-Control')
        @cache_control = {}
      else
        headers['Cache-Control'] = value
        @cache_control = hash.dup.freeze
      end
    end

    # The literal value of the ETag HTTP header or nil if no ETag is specified.
    def etag
      headers['Etag']
    end
  end

  # HTTP request header helpers. When included in Rack::Cache::Request, headers
  # may be accessed by their standard RFC 2616 names using the #headers Hash.
  module RequestHeaders
    include Rack::Cache::Headers

    # A Hash-like object providing access to HTTP request headers.
    def headers
      @headers ||= Rack::Utils::EnvironmentHeaders.new(env)
    end

    # The literal value of the If-Modified-Since request header or nil when
    # no If-Modified-Since header is present.
    def if_modified_since
      headers['If-Modified-Since']
    end

    # The literal value of the If-None-Match request header or nil when
    # no If-None-Match header is present.
    def if_none_match
      headers['If-None-Match']
    end
  end

  # HTTP response header helper methods.
  module ResponseHeaders
    include Rack::Cache::Headers

    # Set of HTTP response codes of messages that can be cached, per
    # RFC 2616.
    CACHEABLE_RESPONSE_CODES = Set.new([200, 203, 300, 301, 302, 404, 410])

    # Determine if the response is "fresh". Fresh responses may be served from
    # cache without any interaction with the origin. A response is considered
    # fresh when it includes a Cache-Control/max-age indicator or Expiration
    # header and the calculated age is less than the freshness lifetime.
    def fresh?
      ttl && ttl > 0
    end

    # Determine if the response is "stale". Stale responses must be validated
    # with the origin before use. This is the inverse of #fresh?.
    def stale?
      !fresh?
    end

    # Determine if the response is worth caching under any circumstance. An
    # object that is cacheable may not necessary be served from cache without
    # first validating the response with the origin.
    #
    # An object that includes no freshness lifetime (Expires, max-age) and that
    # does not include a validator (Last-Modified, Etag) serves no purpose in a
    # cache that only serves fresh or valid objects.
    def cacheable?
      return false unless CACHEABLE_RESPONSE_CODES.include?(status)
      return false if no_store?
      validateable? || fresh?
    end

    # The response includes specific information about its freshness. True when
    # a +Cache-Control+ header with +max-age+ value is present or when the
    # +Expires+ header is set.
    def freshness_information?
      header?('Expires') || !cache_control['max-age'].nil?
    end

    # Determine if the response includes headers that can be used to validate
    # the response with the origin using a conditional GET request.
    def validateable?
      header?('Last-Modified') || header?('Etag')
    end

    # Indicates that the response should not be served from cache without first
    # revalidating with the origin. Note that this does not necessary imply that
    # a caching agent ought not store the response in its cache.
    def no_cache?
      !cache_control['no-cache'].nil?
    end

    # Indicates that the response should not be stored under any circumstances.
    def no_store?
      cache_control['no-store']
    end

    # The date, as specified by the Date header. When no Date header is present,
    # set the Date header to Time.now and return.
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

    # Sets the number of seconds after which the response should no longer
    # be considered fresh. This sets the Cache-Control max-age value.
    def max_age=(value)
      self.cache_control = cache_control.merge('max-age' => value.to_s)
    end

    # The Time when the response should be considered stale. With a
    # Cache-Control/max-age value is present, this is calculated by adding the
    # number of seconds specified to the responses #date value. Falls back to
    # the time specified in the Expires header or returns nil if neither is
    # present.
    def expires_at
      if max_age = cache_control['max-age']
        date + max_age.to_i
      elsif time = headers['Expires']
        Time.httpdate(time)
      end
    end

    # The response's time-to-live in seconds, or nil when no freshness
    # information is present in the response. When the responses #ttl
    # is <= 0, the response may not be served from cache without first
    # revalidating with the origin.
    def ttl
      max_age - age if max_age
    end

    # Set the response's time-to-live to the specified number of seconds. This
    # adjusts the Cache-Control/max-age value.
    def ttl=(seconds)
      self.max_age = age + seconds
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

    # An array of header names given in the Vary header or an empty
    # array when no Vary header is present.
    def vary_header_names
      return [] unless vary = headers['Vary']
      vary.split(/[\s,]+/)
    end

  private
    def now
      @now ||= Time.now
    end
  end

end
