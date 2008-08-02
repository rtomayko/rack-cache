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
