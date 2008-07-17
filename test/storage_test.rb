require "#{File.dirname(__FILE__)}/spec_setup"

describe 'Rack::Cache::Storage' do

  shared_context 'Provider' do

    before(:each) { @cache = create_provider }
    after(:each)  { @cache = nil }

    it 'stores objects with #put' do
      @cache.put 'hello/word', "I'm here"
    end

    it 'returns object stored after storing with #put' do
      @cache.put('hello/world', "I'm here").should.be == "I'm here"
    end

    it 'returns stored objects with #get' do
      @cache.put('foo', 'bar')
      @cache.get('foo').should.be == 'bar'
    end

    it 'stores and returns the value yielded by the block when no object exists with #get' do
      @cache.get('foo') { 'bar' }.should.be == 'bar'
      @cache.get('foo').should.be == 'bar'
    end

    it 'does not invoke block or overwrite existing objects when block provided to #get' do
      @cache.put('foo', 'bar')
      @cache.get('foo').should.be == 'bar'
      @cache.get('foo') { baz }.should.be == 'bar'
      @cache.get('foo') { fail }
    end
  end

  describe 'Memory' do
    behaves_like 'Rack::Cache::Storage	Provider'

    it 'takes a Hash to ::new and uses it' do
      Rack::Cache::Storage::Memory.new('foo' => 'bar').get('foo').
        should.be == 'bar'
    end

    it 'takes no args to ::new and creates a Hash' do
      Rack::Cache::Storage::Memory.new.get('foo').should.be.nil
    end

    def create_provider
      Rack::Cache::Storage::Memory.new
    end
  end

end
