require 'enumerator'
require 'digest/sha1'

module Rack::Cache

  # Stream filter that reads from a source body, writes to a destination IOish
  # object, and records a SHA1 checksum. An instance of this class meets
  # Rack's specification for a response body.
  class EntityStream
    include Enumerable

    # The Body to read from. Must respond to #each and must only yield String
    # values. If the Body responds to close, it will be called after
    # iteration.
    attr_reader :source

    # An IO-like object that receives data as it passes through the filter.
    # Should respond to write, puts, flush, and close.
    attr_reader :dest

    # A Digest::SHA1 object that's fed data as it moves through the filter.
    attr_reader :digest

    # The number of bytes that have moved through the filter.
    attr_reader :size

    # Create a new EntityStream that reads from +source+ and writes to +dest+
    # when the new instance receives an #each. Yield to the block after the
    # filter has fully processed and closed the streams.
    def initialize(source, dest, &finish)
      raise ArgumentError unless source && dest
      @source, @dest = source, dest
      @digest = Digest::SHA1.new
      @size = 0
      @finish = finish
    end

    # The SHA1 checksum represented as a 31 character string of hexadecimals.
    def hexdigest
      digest.hexdigest
    end

    # Read a chunk from source, write it to dest, and yield to the block.
    def each
      return to_enum(:each) if respond_to?(:to_enum) && !block_given?
      source.each do |part|
        @size += part.length
        dest.write(part)
        digest << part
        yield part
      end
    end

    # Must be called in order to complete filter processing. Close the
    # +source+ and +dest+ streams. Yield the EntityStream instance (self)
    # to the block passed to EntityStream#initialize if present.
    def close
      [ source, dest ].each do |receiver|
        receiver.close if receiver.respond_to? :close
      end
      @finish.call self if @finish.respond_to? :call
    end

    # Perform filter fully (but do not close).
    def exhaust!
      each { |part| }
    end

  end

end
