require "#{File.dirname(__FILE__)}/spec_setup"

def cacheable(body=nil)
  [ 200, {}, [body || 'Hi'] ]
end

class Array
  def cache_canonical
    status, headers, body = self
    body = [body.read] if body.respond_to?(:read)
    [ status, headers, body ]
  end
end

shared_context 'A Cache Storage Provider' do
  it 'stores objects with #put' do
    @cache.put 'hello/world', cacheable("I'm here")
    @cache.get('hello/world').should.not.be.nil
  end
  it 'returns stored objects with #get' do
    @cache.put('foo', cacheable('bar'))
    @cache.get('foo').cache_canonical.
      should.be == cacheable('bar')
  end
  it 'returns object stored after storing with #put' do
    @cache.put('hello/world', cacheable("I'm here")).cache_canonical.
      should.be == cacheable("I'm here")
  end
  it 'stores and returns the value yielded by the block when no object exists with #get' do
    @cache.get('foo') { cacheable('bar') }.cache_canonical.
      should.be == cacheable('bar')
    @cache.get('foo').cache_canonical.
      should.be == cacheable('bar')
  end
  it 'does not invoke block or overwrite existing objects when block provided to #get' do
    @cache.put('foo', cacheable('bar'))
    @cache.get('foo').cache_canonical.should.be == cacheable('bar')
    @cache.get('foo') { baz }.cache_canonical.should.be == cacheable('bar')
    @cache.get('foo') { fail 'should not be called' }
  end
end

describe 'Rack::Cache::Storage' do

  describe 'Memory' do
    behaves_like 'A Cache Storage Provider'
    before { @cache = Rack::Cache::Storage::Memory.new }
    describe '::new' do
      it 'takes a Hash and uses it' do
        Rack::Cache::Storage::Memory.new('foo' => cacheable('bar')).get('foo').
          should.be == cacheable('bar')
      end
      it 'uses its own Hash with no args' do
        Rack::Cache::Storage::Memory.new.get('foo').
          should.be.nil
      end
    end
  end

  describe 'DiskBackedMemory' do
    behaves_like 'A Cache Storage Provider'
    before { @cache = Rack::Cache::Storage::DiskBackedMemory.new }
  end

end
