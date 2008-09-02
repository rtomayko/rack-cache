require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/entity_stream'

describe 'Rack::Cache::EntityStream' do

  class MockIO < StringIO
    def initialize(*args, &close)
      super(*args)
      @close = close
      @closed = false
    end
    def close
      @closed = true
      @close.call if @close.respond_to? :call
      super
    end
    def closed?
      @closed
    end
  end

  EntityStream = Rack::Cache::EntityStream

  it 'accepts a source and dest object when created' do
    stream = EntityStream.new(['hello world'], MockIO.new)
    %w[write close puts flush].each do |message|
      stream.dest.should.respond_to message
    end
    stream.source.should.be == ['hello world']
  end

  it 'reads from source and writes to dest when each is invoked with block' do
    expected = ['hello ', 'world!']
    finished = false
    stream = EntityStream.new(expected.dup, MockIO.new)
    stream.each { |part| part.should.be == expected.shift }
    stream.dest.string.should.be == 'hello world!'
  end

  it 'returns an Enumerable when each is invoked without a block' do
    stream = EntityStream.new(['hello world'], MockIO.new)
    stream.each.should.respond_to :each
    called = false
    stream.each do |part|
      called = true
      part.should.be == 'hello world'
    end
    called.should.be true
  end

  it 'calls the finish block when closed' do
    finished = false
    EntityStream.new([], MockIO.new) { finished = true }.close
    finished.should.be true
  end

  it 'closes dest when closed' do
    stream = EntityStream.new([], MockIO.new)
    stream.close
    stream.dest.should.be.closed
  end

  it 'closes source when closed when source responds to close' do
    source, closed = [], false
    (class<<source;self;end).send(:define_method, :close) { closed = true }
    EntityStream.new(source, MockIO.new).close
    closed.should.be == true
  end

  it 'should generate a SHA hexdigest' do
    stream = EntityStream.new(['Hello World'], MockIO.new)
    stream.exhaust!
    stream.hexdigest.should.be == '0a4d55a8d778e5022fab701977c5d840bbc486d0'
  end

end
