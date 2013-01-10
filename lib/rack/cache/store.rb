require 'rack/cache/key'

module Rack::Cache

  # The MetaStore is responsible for storing meta information about a
  # request/response pair keyed by the request's URL.
  #
  # The meta store keeps a list of request/response pairs for each canonical
  # request URL. A request/response pair is a two element Array of the form:
  #   [request, response]
  #
  # The +request+ element is a Hash of Rack environment keys. Only protocol
  # keys (i.e., those that start with "HTTP_") are stored. The +response+
  # element is a Hash of cached HTTP response headers for the paired request.
  #
  # The MetaStore class is abstract and should not be instanstiated
  # directly. Concrete subclasses should implement the protected #read,
  # #write, and #purge methods. Care has been taken to keep these low-level
  # methods dumb and straight-forward to implement.
  class Store

    def initialize(metastore, entitystore)
      @metastore, @entitystore = metastore, entitystore
    end

    # Locate a cached response for the request provided. Returns a
    # Rack::Cache::Response object if the cache hits or nil if no cache entry
    # was found.
    def lookup(request)
      key = cache_key(request)
      entries = @metastore[key]

      # bail out if we have nothing cached
      return nil unless entries

      # find a cached entry that matches the request.
      env = request.env
      match = entries.detect{|req,res| requests_match?(res['Vary'], env, req)}
      return nil if match.nil?

      _, res = match
      if body = @entitystore[res['X-Content-Digest']]
        restore_response(res, [body])
      else
        # TODO the metastore referenced an entity that doesn't exist in
        # the entitystore. we definitely want to return nil but we should
        # also purge the entry from the meta-store when this is detected.
      end
    end

    # Write a cache entry to the store under the given key. Existing
    # entries are read and any that match the response are removed.
    # This method calls #write with the new list of cache entries.
    def store(request, response)
      key = cache_key(request)
      stored_env = persist_request(request)

      # write the response body to the entity store if this is the
      # original response.
      if response.headers['X-Content-Digest'].nil?
        digest, size, buf = slurp(response.body)
        if request.env['rack-cache.use_native_ttl'] && response.fresh?
          @entitystore.store(digest, buf, :expires => response.ttl)
        else
          @entitystore.store(digest, buf)
        end
        response.headers['X-Content-Digest'] = digest
        response.headers['Content-Lengths'] = size.to_s unless response.headers['Transfer-Encoding']
        body = @entitystore[digest]
        response.body = [body] if body
      end

      # read existing cache entries, remove non-varying, and add this one to
      # the list
      vary = response.vary
      entries =
        @metastore[key].to_a.reject do |env,res|
          (vary == res['Vary']) &&
            requests_match?(vary, env, stored_env)
        end

      headers = persist_response(response)
      headers.delete 'Age'

      entries.unshift [stored_env, headers]
      @metastore[key] = entries
      key
    end

    # Generate a cache key for the request.
    def cache_key(request)
      keygen = request.env['rack-cache.cache_key'] || Key
      keygen.call(request)
    end

    # Invalidate all cache entries that match the request.
    def invalidate(request)
      modified = false
      key = cache_key(request)
      entries =
        @metastore[key].to_a.map do |req, res|
          response = restore_response(res)
          if response.fresh?
            response.expire!
            modified = true
            [req, persist_response(response)]
          else
            [req, res]
          end
        end
      @metastore[key] = entries if modified
    end

  private

    def slurp(body)
      buf, digest = [], Digest::SHA1.new
      body.each do |part|
        digest << part
        buf << part
      end
      body.close if body.respond_to? :close
      buf = buf.join
      [digest.hexdigest, buf.bytesize, buf]
    end

    # Extract the environment Hash from +request+ while making any
    # necessary modifications in preparation for persistence. The Hash
    # returned must be marshalable.
    def persist_request(request)
      env = request.env.dup
      env.reject! { |key,val| key =~ /[^0-9A-Z_]/ || !val.respond_to?(:to_str) }
      env
    end

    # Converts a stored response hash into a Response object. The caller
    # is responsible for loading and passing the body if needed.
    def restore_response(hash, body=nil)
      status = hash.delete('X-Status').to_i
      Rack::Cache::Response.new(status, hash, body)
    end

    def persist_response(response)
      hash = response.headers.to_hash
      hash['X-Status'] = response.status.to_s
      hash
    end

    # Determine whether the two environment hashes are non-varying based on
    # the vary response header value provided.
    def requests_match?(vary, env1, env2)
      return true if vary.nil? || vary == ''
      vary.split(/[\s,]+/).all? do |header|
        key = "HTTP_#{header.upcase.tr('-', '_')}"
        env1[key] == env2[key]
      end
    end
  end
end
