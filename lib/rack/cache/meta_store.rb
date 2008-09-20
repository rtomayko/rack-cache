require 'fileutils'
require 'digest/sha1'

module Rack::Cache

  # The meta store is responsible for storing and retrieving negotiation
  # tuples keyed by request URL.
  #
  # == Negotiation Tuples
  #
  # The meta store keeps a list of "negotiation tuples" for each canonical
  # request URL. A negotiation tuple is a two element Array of the form:
  #   [request, response]
  #
  # The +request+ element is a Hash of Rack environment keys. Only protocol
  # keys (i.e., those that start with "HTTP_") are stored. The +response+
  # element is a Hash of cached HTTP response headers for the paired request.
  #
  # == Backing Implementations
  #
  # The MetaStore class is abstract and should not be instanstiated
  # directly. Concrete subclasses should implement the protected #read,
  # #write, and #purge methods. Care has been taken to keep these low-level
  # methods dumb and straight-forward to implement.
  #
  class MetaStore

    # Headers that should not be stored in cache (from RFC 2616).
    HEADER_BLACKLIST = Set.new(%w[
      Connection
      Keep-Alive
      Proxy-Authenticate
      Proxy-Authorization
      TE
      Trailers
      Transfer-Encoding
      Upgrade
    ])

    # Locate a cached response for the request provided. Returns a
    # Rack::Cache::Response object if the cache hit or nil if no cached
    # object was found.
    def lookup(request, entity_store)
      entries = read(request.fullpath)

      # bail out if we have nothing cached
      return nil if entries.empty?

      # find a cached entry that matches the request.
      match =
        entries.detect do |req,res|
          vary = res['Vary']
          vary.nil? || (vary == '') || requests_match?(vary, request.env, req)
        end

      # bail out if nothing matched
      return nil if match.nil?

      # reconstruct response object
      # TODO what if body doesn't exist in entity store?
      req, res = match
      status = res['X-Status']
      body = entity_store.open(res['X-Content-Digest'])
      response = Rack::Cache::Response.new(status.to_i, res, body)
      response.activate!

      # Return the cached response
      response
    end

    # Write a cache entry to the store under the given key. Existing
    # entries are read and any that match the response are removed.
    # This method calls #write with the new list of cache entries.
    #--
    # TODO canonicalize URL key
    def store(request, response, entity_store)
      key = request.fullpath
      req = persist_request(request)
      res = persist_response(response)

      # write the response body to the entity store if this is the
      # original response.
      if res['X-Content-Digest'].nil?
        digest, size = entity_store.write(response.body)
        res['X-Content-Digest'] = digest
        res['Content-Length'] = size.to_s
        response.body = entity_store.open(digest)
      end

      # read existing cache entries, remove non-varying, and add this one to
      # the list
      vary = res['Vary']
      entries =
        read(key).reject do |ereq,eres|
          (vary == eres['Vary']) && requests_match?(vary, ereq, req)
        end
      entries.unshift [req, res]
      write key, entries
    end

  private
    # Extract the environment Hash from +request+ while making any
    # necessary modifications in preparation for persistence. The Hash
    # returned must be marshalable.
    def persist_request(request)
      env = request.env.dup
      env.reject! { |key,val| key =~ /[^0-9A-Z_]/ }
      env
    end

    # Extract the headers Hash from +response+ while making any
    # necessary modifications in preparation for persistence. The Hash
    # returned must be marshalable.
    def persist_response(response)
      headers = response.headers.reject { |k,v| HEADER_BLACKLIST.include?(k) }
      headers['X-Status'] = response.status.to_s
      headers
    end


    # Determine whether the two environment hashes are non-varying based on
    # the vary response header value provided.
    def requests_match?(vary, env1, env2)
      return true if vary.nil? || vary == ''
      vary.split(/\s+/).all? do |header|
        key = "HTTP_#{header.upcase.tr('-', '_')}"
        env1[key] == env2[key]
      end
    end

  protected
    # Locate all cached negotiations that match the specified request
    # URL key. The result must be an Array of all cached negotation
    # tuples. An empty Array must be returned if nothing is cached for
    # the specified key.
    def read(key)
      raise NotImplemented
    end

    # Store an Array of negotiation tuples for the given key. Concrete
    # implementations should not attempt to filter or concatenate the
    # list in any way.
    def write(key, negotiations)
      raise NotImplemented
    end

    # Remove all cached entries at the key specified. No error is raised
    # when the key does not exist.
    def purge(key)
      raise NotImplemented
    end

    def default_entity_store
      raise NotImplemented
    end

    # Generate a SHA-1 hex digest for the specified string. This is a
    # simple utility method for meta store implementations.
    def hexdigest(data)
      Digest::SHA1.hexdigest(data)
    end

  public

    # Concrete MetaStore implementation that uses a simple Hash to store
    # negotiations on the heap.
    class Heap < MetaStore
      def initialize(hash={})
        @hash = hash
      end

      def read(key)
        @hash.fetch(key, [])
      end

      def write(key, entries)
        @hash[key] = entries
      end

      def purge(key)
        @hash.delete(key)
        nil
      end

      def default_entity_store
        Rack::Cache::EntityStore::Heap
      end

      def to_hash
        @hash
      end
    end

    # Concrete MetaStore implementation that stores negotiations on disk.
    class Disk < MetaStore

      attr_reader :root

      def initialize(root="/tmp/rack-cache/meta-#{ARGV[0]}")
        @root = File.expand_path(root)
        FileUtils.mkdir_p(root, :mode => 0755)
      end

      def read(key)
        path = key_path(key)
        File.open(path, 'rb') { |io| Marshal.load(io) }
      rescue Errno::ENOENT
        []
      end

      def write(key, entries)
        path = key_path(key)
        File.open(path, 'wb') { |io| Marshal.dump(entries, io, -1) }
      rescue Errno::ENOENT
        Dir.mkdir(File.dirname(path), 0755)
        retry
      end

      def purge(key)
        path = key_path(key)
        File.unlink(path)
        nil
      rescue Errno::ENOENT
        nil
      end

      def default_entity_store
        Rack::Cache::EntityStore::Disk
      end

    private
      def key_path(key)
        File.join(root, spread(hexdigest(key)))
      end

      def spread(sha, n=2)
        sha = sha.dup
        sha[n,0] = '/'
        sha
      end

    end

    # Stores negotiation meta information in memcached. Keys are not stored
    # directly since memcached has a 250-byte limit on key names. Instead,
    # the SHA-1 hexdigest of the key is used.
    class MemCache < MetaStore

      # A Memcached instance.
      attr_reader :cache

      def initialize(server="localhost:11211")
        @cache =
          if server.respond_to?(:stats)
            server
          else
            require 'memcached'
            Memcached.new(server)
          end
      end

      def read(key)
        key = hexdigest(key)
        cache.get(key)
      rescue Memcached::NotFound
        []
      end

      def write(key, entries)
        key = hexdigest(key)
        cache.set(key, entries)
      end

      def purge(key)
        key = hexdigest(key)
        cache.delete(key)
        nil
      rescue Memcached::NotFound
        nil
      end

      def default_entity_store
        Rack::Cache::EntityStore::Disk
      end
    end

  end

end
