require 'rack/cache/entity_stream'

module Rack::Cache

  # Entity stores are used to cache response bodies across requests. All
  # Implementations are required to calculate a SHA checksum of the data written
  # which becomes the response body's key.
  #--
  # TODO document pros and cons of different EntityStore implementations
  module EntityStore

    # Stores entity bodies on the heap using a Hash object.
    class Heap

      # Create the store with the specified backing Hash.
      def initialize(hash={})
        @hash = hash
      end

      # Determine whether the response body with the specified key (SHA)
      # exists in the store.
      def exist?(key)
        @hash.include?(key)
      end

      # Read all data associated with the given key and return as a single
      # String.
      def read(key)
        @hash[key]
      end

      # Return an object suitable for use as a Rack response body for the
      # specified key.
      def open(key)
        [ read(key) ] if exist?(key)
      end

      # Write the Rack response body immediately and return the SHA key.
      def write(body)
        key = nil
        io = queue(body) { |key| }
        io.each { }
        io.close
        key
      end

      # Queue the Rack response body provided for eventual write to the
      # backing store. Returns a Rack response body that should replace the
      # body provided. When the returned body is closed, the block is invoked
      # with the key used.
      def queue(body, &block)
        EntityStream.new body, StringIO.new do |filter|
          key = filter.hexdigest
          @hash[key] = filter.dest.string
          block.call key unless block.nil?
        end
      end

    end


    # Stores entity bodies on disk at the specified path.
    class Disk

      # Path where entities should be stored. This directory is
      # created the first time the store is instansiated if it does not
      # already exist.
      attr_reader :root

      def initialize(root="/tmp/rc-entity")
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

      def open(key)
        File.open(body_path(key), 'rb')
      rescue Errno::ENOENT
        nil
      end

      def write(body)
        key = nil
        io = queue(body) {|key|}
        io.each {}
        io.close
        key
      end

      def queue(body, &block)
        filename = ['in', $$, Thread.current.object_id].join('-')
        temp_file = storage_path(filename)
        dest = File.open(temp_file, 'wb')
        EntityStream.new body, dest do |filter|
          key = filter.hexdigest
          path = body_path(key)
          if File.exist?(path)
            File.unlink temp_file
          else
            FileUtils.mkdir_p File.dirname(path), :mode => 0755
            FileUtils.mv temp_file, path
          end
          block.call key unless block.nil?
        end
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
