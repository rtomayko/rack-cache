require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/config'

class MockConfig
  include Rack::Cache::Config

  def configured!
    @configured = true
  end

  def configured?
    @configured
  end
end

describe 'Rack::Cache::Config' do

  before(:each) { @config = MockConfig.new }

  it 'has events and trace variables after creation' do
    @config.events.should.not.be.nil
    @config.trace.should.not.be.nil
  end


  it 'executes event handlers' do
    executed = false
    @config.on(:foo) { executed = true }
    @config.perform :foo
    executed.should.be true
  end

  it 'executes multiple handlers in LOFO (last-on, first-off order)' do
    x = 'nothing executed'
    @config.on :foo do
      x.should.be == 'bottom executed'
      x = 'top executed'
    end
    @config.on :foo do
      x.should.be == 'nothing executed'
      x = 'bottom executed'
    end
    @config.perform :foo
    x.should.be == 'top executed'
  end

  it 'records event execution history' do
    @config.on(:foo) {}
    @config.perform :foo
    @config.should.a.performed? :foo
  end

  it 'raises an exception when asked to perform an unknown event' do
    assert_raises RuntimeError do
      @config.perform :foo
    end
  end

  it 'runs events when a message matching the event name is sent to the receiver' do
    x = 'not executed'
    @config.on(:foo) { x = 'executed' }
    @config.should.respond_to :foo
    @config.foo
    x.should.be == 'executed'
  end

  it 'fully transitions out of handlers when the next event is invoked' do
    x = []
    @config.on(:foo) {
      x << 'in foo, before transitioning to bar'
      bar
      x << 'in foo, after transitioning to bar'
    }
    @config.on(:bar) { x << 'in bar' }
    @config.perform :foo
    x.should.be == [
      'in foo, before transitioning to bar',
      'in bar'
    ]
  end

  it 'raises an exception when asked to transition to an unknown event' do
    @config.on(:foo) { transition :bar }
    assert_raises RuntimeError do
      @config.perform :foo
    end
  end

  describe '#import' do

    before :each do
      @config = MockConfig.new
      @tempdir = create_temp_directory
      $:.unshift @tempdir
    end

    after :each do
      @config = nil
      $:.shift if $:.first == @tempdir
      remove_entry_secure @tempdir
    end

    def make_temp_file(filename, data='configured!')
      create_temp_file @tempdir, filename, data
    end

    it 'loads config files from the load path when file is relative' do
      make_temp_file 'foo/bar.rb'
      @config.import 'foo/bar.rb'
      @config.should.be.configured
    end

    it 'assumes a .rb file extension when no file extension exists' do
      make_temp_file 'foo/bar.rb'
      @config.import 'foo/bar'
      @config.should.be.configured
    end

    it 'does not assume a .rb file extension when other file extension exists' do
      make_temp_file 'foo/bar.conf'
      @config.import 'foo/bar.conf'
      @config.should.be.configured
    end

    it 'should locate files with absolute path names' do
      make_temp_file 'foo/bar.rb'
      @config.import File.join(@tempdir, 'foo/bar.rb')
      @config.should.be.configured
    end

    it 'raises a LoadError when the file cannot be found' do
      assert_raises(LoadError) {
        @config.import('this/file/is/very-likely/not/to/exist.rb')
      }
    end

    it 'executes within the context of the object instance' do
      make_temp_file 'foo/bar.rb',
        'self.should.be.kind_of Rack::Cache::Config ; configured!'
      @config.import 'foo/bar'
      @config.should.be.configured
    end

  end

end
