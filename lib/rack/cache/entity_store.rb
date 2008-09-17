require 'digest/sha1'

module Rack::Cache

  # Entity stores are used to cache response bodies across requests. All
  # Implementations are required to calculate a SHA checksum of the data written
  # which becomes the response body's key.
  #--
  # TODO document pros and cons of different EntityStore implementations
  class EntityStore

    # Read all data associated with the given key and return as a single
    # String.
    def read(key)
      raise NotImplemented
    end

    # Read body calculating the SHA1 checksum and size while
    # yielding each chunk to the block. If the body responds to close,
    # call it after iteration is complete. Return a two-tuple of the form:
    # [ hexdigest, size ].
    def slurp(body)
      digest, size = Digest::SHA1.new, 0
      body.each do |part|
        size += part.length
        digest << part
        yield part
      end
      body.close if body.respond_to? :close
      [ digest.hexdigest, size ]
    end

    private :slurp


    # Stores entity bodies on the heap using a Hash object.
    class Heap < EntityStore

      # Create the store with the specified backing Hash.
      def initialize(hash={})
        @hash = hash
      end

      # Determine whether the response body with the specified key (SHA)
      # exists in the store.
      def exist?(key)
        @hash.include?(key)
      end

      # Return an object suitable for use as a Rack response body for the
      # specified key.
      def open(key)
        (body = @hash[key]) && body.dup
      end

      # Read all data associated with the given key and return as a single
      # String.
      def read(key)
        (body = @hash[key]) && body.join
      end

      # Write the Rack response body immediately and return the SHA key.
      def write(body)
        buf = []
        key, size = slurp(body) { |part| buf << part }
        @hash[key] = buf
        [key, size]
      end

    end


    # Stores entity bodies on disk at the specified path.
    class Disk < EntityStore

      # Path where entities should be stored. This directory is
      # created the first time the store is instansiated if it does not
      # already exist.
      attr_reader :root

      def initialize(root="/tmp/rack-cache/entity")
        @root = root
        FileUtils.mkdir_p root, :mode => 0755
      end

      def exist?(key)
        File.exist?(body_path(key))
      end

      def read(key)
        File.read(body_path(key))
      rescue Errno::ENOENT
        nil
      end

      # Open the entity body and return an IO object. The IO object's
      # each method is overridden to read 4K blocks instead of lines.
      def open(key)
        io = File.open(body_path(key), 'rb')
        def io.each
          while part = read(4096)
            yield part
          end
        end
        io
      rescue Errno::ENOENT
        nil
      end

      def write(body)
        filename = ['buf', $$, Thread.current.object_id].join('-')
        temp_file = storage_path(filename)
        key, size =
          File.open(temp_file, 'wb') { |dest|
            slurp(body) { |part| dest.write(part) }
          }

        path = body_path(key)
        if File.exist?(path)
          File.unlink temp_file
        else
          FileUtils.mkdir_p File.dirname(path), :mode => 0755
          FileUtils.mv temp_file, path
        end
        [key, size]
      end

    protected

      def storage_path(stem)
        File.join root, stem
      end

      def spread(key)
        key = key.dup
        key[2,0] = '/'
        key
      end

      def body_path(key)
        storage_path spread(key)
      end

    end

  end

end
