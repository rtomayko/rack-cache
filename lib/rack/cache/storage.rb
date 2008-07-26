require 'enumerator'
require 'rack/utils'
require 'digest/sha1'

module Rack::Cache

  # Rack::Cache supports pluggable storage backends.
  #
  # == Cacheable Objects
  #
  # Storage providers are responsible for storing, retreiving,
  # and purging "cacheable objects". A cacheable object is a
  # constrained version of the response object defined by Rack:
  #
  # http://rack.rubyforge.org/doc/files/SPEC.html
  #
  # A Rack response object is a three-element array that contains
  # the HTTP response status code, a Hash of HTTP headers, and a
  # response body:
  #   [ status, headers, body ]
  #
  module Storage

    # Storage Provider interface and abstract base class.
    class Provider

      # Retrieve a cacheable object for the key provided.
      def get(key)
        if value = fetch(key)
          value
        elsif block_given?
          put key, yield
        end
      end

      def put(key, value)
        store key, value
      end

      def delete(key)
        store key, nil
      end

      def replace(key, value)
        store key, value if get(key)
      end

    protected

      def fetch(key)
        raise NotImplemented
      end

      def store(key, object)
        raise NotImplemented
      end

      def flush
        raise NotImplemented
      end

    private

      # Return an idempotent version of a Rack response body. When the
      # object provided is an Array, return the body provided. Otherwise
      # read the body into an Array, call the close method, and return
      # the Array.
      def slurp(body)
        if body.kind_of?(Array)
          body
        else
          data = []
          body.each { |part| data << part }
          body.close if body.respond_to? :close
          data
        end
      end

    end


    # Stores cached entries in memory using a normal Hash object. Note that
    # entire response bodies are kept on the heap until purged or deleted.
    class Memory < Provider

      def initialize(hashish={})
        @contents = hashish
      end

      def delete(key)
        @contents.delete(key)
      end

      def to_hash
        @contents
      end

    protected

      def fetch(key)
        @contents[key]
      end

      def store(key, object)
        status, headers, body = object
        data = slurp(body)
        @contents[key] = [ status, headers, data ]
      end

    end


    # A simple Hash-based memory store that writes bodies to disk.
    class DiskBackedMemory < Memory
      include FileUtils

      def initialize(storage_root="/tmp/r#{$$}")
        @storage_root = storage_root
        mkdir_p @storage_root
        super()
      end

    protected

      def fetch(key)
        if object = super
          status, headers, sha = object
          [ status, headers, disk_read(sha) ]
        end
      end

      def store(key, object)
        status, headers, body = object
        sha = disk_write(body)
        @contents[key] = [ status, headers, sha ]
        [ status, headers, disk_read(sha) ]
      end

      def delete(key)
        if object = super
          status, headers, sha = object
          F.unlink body_path(sha)
        end
      end

    private

      F = File
      D = Dir

      def storage_path(stem)
        F.join(@storage_root, stem)
      end

      def partition_sha(sha)
        sha = sha.dup
        sha[2,0] = '/'
        sha
      end

      def body_path(sha)
        storage_path(partition_sha(sha))
      end

      # Write body to disk and return the SHA1 checksum.
      def disk_write(body)
        # TODO can only write one body at a time
        temp_file = storage_path("+#{$$}")
        digest = Digest::SHA1.new
        F.open(temp_file, 'w') do |wr|
          body.each do |part|
            digest << part
            wr.write(part)
          end
        end
        sha = digest.hexdigest
        path = body_path(sha)
        mkdir_p F.dirname(path)
        mv temp_file, path
        sha
      end

      # Open the file stored for the corresponding SHA1
      # checksum.
      def disk_read(sha)
        F.exist?(path = body_path(sha)) && F.open(path, 'rb')
      end

    end

  end

end
