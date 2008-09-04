require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/meta_store'

describe_shared 'A Rack::Cache::MetaStore Implementation' do

  before do
    @request = mock_request('/', {})
    @response = mock_response(200, {}, ['hello world'])
    @entity_store = nil
  end

  # Low-level implementation methods ===========================================

  it 'writes a list of negotation tuples with #write' do
    @store.write('/test', [[{}, {}]])
  end

  it 'reads a list of negotation tuples with #read' do
    @store.write('/test', [[{},{}],[{},{}]])
    tuples = @store.read('/test')
    tuples.should.be == [ [{},{}], [{},{}] ]
  end

  it 'reads an empty list with #read when nothing cached at key' do
    @store.read('/nothing').should.be.empty
  end

  it 'removes entries for key with #purge' do
    @store.write('/test', [[{},{}]])
    @store.read('/test').should.not.be.empty

    @store.purge('/test')
    @store.read('/test').should.be.empty
  end

  it 'returns purged entries from #purge' do
    @store.write('/test', [[{},{}]])
    @store.purge('/test').should.be == [[{},{}]]
    @store.purge('/test').should.be.empty
  end

  # Abstract methods ===========================================================

  define_method :queue_simple_entry do
    @request = mock_request('/test', {})
    @response = mock_response(200, {'Cache-Control' => 'max-age=420'}, ['test'])
    body = @response.body
    @store.queue(@request, @response, entity_store)
    @response.body.should.not.be body
  end

  it 'should prepare but not store new cache entry with #queue' do
    queue_simple_entry
    @store.read('/test').should.be.empty
  end

  define_method :queue_and_store_simple_entry do
    queue_simple_entry
    @response.body.each{}
    @response.body.close
  end

  it 'should store queued cache entry after response body is closed' do
    queue_and_store_simple_entry
    @store.read('/test').should.not.be.empty
  end

  it 'should set the X-Content-Digest response header before storing' do
    queue_and_store_simple_entry
    req, res = @store.read('/test').first
    res['X-Content-Digest'].should.be == 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'
  end

  it 'should find a stored entry with #lookup' do
    queue_and_store_simple_entry
    response = @store.lookup(@request, entity_store)
    response.should.not.be.nil
    response.should.be.kind_of Rack::Cache::Response
  end

  it 'should restore response headers properly with #lookup' do
    queue_and_store_simple_entry
    response = @store.lookup(@request, entity_store)
    response.headers.reject{|k,v| k =~ /^X-/}.
      should.be == @response.headers.merge('Age' => '0')
  end

  it 'should restore response body from entity store with #lookup' do
    queue_and_store_simple_entry
    response = @store.lookup(@request, entity_store)
    body = '' ; response.body.each {|p| body << p}
    body.should.be == 'test'
  end

  # Helper Methods =============================================================

  define_method :mock_request do |uri,opts|
    env = Rack::MockRequest.env_for(uri, opts || {})
    Rack::Cache::Request.new(env)
  end

  define_method :mock_response do |status,headers,body|
    headers ||= {}
    body = Array(body).compact
    Rack::Cache::Response.new(status, headers, body)
  end

  define_method :entity_store do ||
    @entity_store ||= @store.default_entity_store.new
  end

end

describe 'Rack::Cache::MetaStore' do

  describe 'Heap' do
    it_should_behave_like 'A Rack::Cache::MetaStore Implementation'
    before { @store = Rack::Cache::MetaStore::Heap.new }
  end

  describe 'Disk' do
    it_should_behave_like 'A Rack::Cache::MetaStore Implementation'
    before do
      @temp_dir = create_temp_directory
      @store = Rack::Cache::MetaStore::Disk.new("#{@temp_dir}/meta")
      @entity_store = Rack::Cache::EntityStore::Disk.new("#{@temp_dir}/entity")
    end
    after do
      @store, @entity_store = nil
      remove_entry_secure @temp_dir
    end
  end
end
