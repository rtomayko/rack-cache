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
        headers['Cache-Control'].to_s.delete(' ').split(',').inject({}) {|hash,token|
          name, value = token.split('=', 2)
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

    # Indicates that the response should not be served from cache without first
    # revalidating with the origin. Note that this does not necessary imply that
    # a caching agent ought not store the response in its cache.
    def no_cache?
      cache_control['no-cache']
    end

    # The value of the Cache-Control max-age directive as a Fixnum, or nil
    # when no max-age directive is present.
    def max_age
      age = cache_control['max-age'] && age.to_i
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

    # Status codes of responses that MAY be stored by a cache or used in reply
    # to a subsequent request.
    #
    # http://tools.ietf.org/html/rfc2616#section-13.4
    CACHEABLE_RESPONSE_CODES = [
      200, # OK
      203, # Non-Authoritative Information
      300, # Multiple Choices
      301, # Moved Permanently
      302, # Found
      404, # Not Found
      410  # Gone
    ].to_set

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

    # Determine if the response is worth caching under any circumstance. Responses
    # marked "private" with an explicit Cache-Control directive are considered
    # uncacheable
    #
    # Responses with neither a freshness lifetime (Expires, max-age) nor cache
    # validator (Last-Modified, Etag) are considered uncacheable.
    def cacheable?
      return false unless CACHEABLE_RESPONSE_CODES.include?(status)
      return false if no_store? || private?
      validateable? || fresh?
    end

    # The response includes specific information about its freshness. True when
    # a +Cache-Control+ header with +max-age+ value is present or when the
    # +Expires+ header is set.
    def freshness_information?
      header?('Expires') ||
        !!(cache_control['s-maxage'] || cache_control['max-age'])
    end

    # Determine if the response includes headers that can be used to validate
    # the response with the origin using a conditional GET request.
    def validateable?
      header?('Last-Modified') || header?('Etag')
    end

    # Indicates that the response should not be stored under any circumstances.
    def no_store?
      cache_control['no-store']
    end

    # True when the response has been explicitly marked "public".
    def public?
      cache_control['public']
    end

    # Mark the response "public", making it eligible for other clients. Note
    # that responses are considered "public" by default unless the request
    # includes private headers (Authorization, Cookie).
    def public=(value)
      value = value ? true : nil
      self.cache_control = cache_control.
        merge('public' => value, 'private' => !value)
    end

    # True when the response has been marked "private" explicitly.
    def private?
      cache_control['private']
    end

    # Mark the response "private", making it ineligible for serving other
    # clients.
    def private=(value)
      value = value ? true : nil
      self.cache_control = cache_control.
        merge('public' => !value, 'private' => value)
    end

    # Indicates that the cache must not serve a stale response in any
    # circumstance without first revalidating with the origin. When present,
    # the TTL of the response should not be overriden to be greater than the
    # value provided by the origin.
    def must_revalidate?
      cache_control['must-revalidate'] ||
      cache_control['proxy-revalidate']
    end

    # The date, as specified by the Date header. When no Date header is present,
    # set the Date header to Time.now and return.
    def date
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
    # check for a s-maxage directive, then a max-age directive, and then fall
    # back on an expires header; return nil when no maximum age can be
    # established.
    def max_age
      if age = (cache_control['s-maxage'] || cache_control['max-age'])
        age.to_i
      elsif headers['Expires']
        Time.httpdate(headers['Expires']) - date
      end
    end

    # The number of seconds after which the response should no longer
    # be considered fresh. Sets the Cache-Control max-age directive.
    def max_age=(value)
      self.cache_control = cache_control.merge('max-age' => value.to_s)
    end

    # Like #max_age= but sets the s-maxage directive, which applies only
    # to shared caches.
    def shared_max_age=(value)
      self.cache_control = cache_control.merge('s-maxage' => value.to_s)
    end

    # The Time when the response should be considered stale. With a
    # Cache-Control/max-age value is present, this is calculated by adding the
    # number of seconds specified to the responses #date value. Falls back to
    # the time specified in the Expires header or returns nil if neither is
    # present.
    def expires_at
      if max_age = (cache_control['s-maxage'] || cache_control['max-age'])
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

    # Set the response's time-to-live for shared caches to the specified number
    # of seconds. This adjusts the Cache-Control/s-maxage directive.
    def ttl=(seconds)
      self.shared_max_age = age + seconds
    end

    # Set the response's time-to-live for private/client caches. This adjusts
    # the Cache-Control/max-age directive.
    def client_ttl=(seconds)
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

    # Determine if response's ETag matches the etag value provided. Return
    # false when either value is nil.
    def etag_matches?(etag)
      etag && self.etag == etag
    end

    # Headers that MUST NOT be included with 304 Not Modified responses.
    #
    # http://tools.ietf.org/html/rfc2616#section-10.3.5
    NOT_MODIFIED_OMIT_HEADERS = %w[
      Allow
      Content-Encoding
      Content-Language
      Content-Length
      Content-Md5
      Content-Type
      Last-Modified
    ].to_set

    # Modify the response so that it conforms to the rules defined for
    # '304 Not Modified'. This sets the status, removes the body, and
    # discards any headers that MUST NOT be included in 304 responses.
    #
    # http://tools.ietf.org/html/rfc2616#section-10.3.5
    def not_modified!
      self.status = 304
      self.body = []
      NOT_MODIFIED_OMIT_HEADERS.each { |name| headers.delete(name) }
      nil
    end

    # The literal value of the Vary header, or nil when no header is present.
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
