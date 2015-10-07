# coding: utf-8
require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/entitystore'
require 'rack/cache/metastore'

class Object
  def sha_like?
    length == 40 && self =~ /^[0-9a-z]+$/
  end
end

module RackCacheEntityStoreImplementation
  def self.included(base)
    base.class_eval do
      it 'responds to all required messages' do
        %w[read open write exist?].each do |message|
          assert @store.respond_to? message
        end
      end

      it 'stores bodies with #write' do
        key, size = @store.write(['My wild love went riding,'])
        refute key.nil?
        assert key.sha_like?

        data = @store.read(key)
        data.must_equal 'My wild love went riding,'
      end

      it 'takes a ttl parameter for #write' do
        key, size = @store.write(['My wild love went riding,'], 0)
        refute key.nil?
        assert key.sha_like?

        data = @store.read(key)
        data.must_equal 'My wild love went riding,'
      end

      it 'correctly determines whether cached body exists for key with #exist?' do
        key, size = @store.write(['She rode to the devil,'])
        assert @store.exist? key
        refute @store.exist? '938jasddj83jasdh4438021ksdfjsdfjsdsf'
      end

      it 'can read data written with #write' do
        key, size = @store.write(['And asked him to pay.'])
        data = @store.read(key)
        data.must_equal 'And asked him to pay.'
      end

      it 'gives a 40 character SHA1 hex digest from #write' do
        key, size = @store.write(['she rode to the sea;'])
        refute key.nil?
        key.length.must_equal 40
        key.must_match /^[0-9a-z]+$/
        key.must_equal '90a4c84d51a277f3dafc34693ca264531b9f51b6'
      end

      it 'returns the entire body as a String from #read' do
        key, size = @store.write(['She gathered together'])
        @store.read(key).must_equal 'She gathered together'
      end

      it 'returns nil from #read when key does not exist' do
        @store.read('87fe0a1ae82a518592f6b12b0183e950b4541c62').must_equal nil
      end

      it 'returns a Rack compatible body from #open' do
        key, size = @store.write(['Some shells for her hair.'])
        body = @store.open(key)
        assert body.respond_to? :each
        buf = ''
        body.each { |part| buf << part }
        buf.must_equal 'Some shells for her hair.'
      end

      it 'returns nil from #open when key does not exist' do
        @store.open('87fe0a1ae82a518592f6b12b0183e950b4541c62').must_equal nil
      end

      it 'can store largish bodies with binary data' do
        pony = File.open(File.dirname(__FILE__) + '/pony.jpg', 'rb') { |f| f.read }
        key, size = @store.write([pony])
        key.must_equal 'd0f30d8659b4d268c5c64385d9790024c2d78deb'
        data = @store.read(key)
        data.length.must_equal pony.length
        data.hash.must_equal pony.hash
      end

      it 'deletes stored entries with #purge' do
        key, size = @store.write(['My wild love went riding,'])
        @store.purge(key).must_equal nil
        @store.read(key).must_equal nil
      end
    end
  end
end

describe 'Rack::Cache::EntityStore' do

  describe 'Heap' do
    before { @store = Rack::Cache::EntityStore::Heap.new }
    include RackCacheEntityStoreImplementation
    it 'takes a Hash to ::new' do
      @store = Rack::Cache::EntityStore::Heap.new('foo' => ['bar'])
      @store.read('foo').must_equal 'bar'
    end
    it 'uses its own Hash with no args to ::new' do
      @store.read('foo').must_equal nil
    end
  end

  describe 'Disk' do
    before do
      @temp_dir = create_temp_directory
      @store = Rack::Cache::EntityStore::Disk.new(@temp_dir)
    end
    after do
      @store = nil
      remove_entry_secure @temp_dir
    end
    include RackCacheEntityStoreImplementation

    it 'takes a path to ::new and creates the directory' do
      path = @temp_dir + '/foo'
      @store = Rack::Cache::EntityStore::Disk.new(path)
      assert File.directory? path
    end
    it 'produces a body that responds to #to_path' do
      key, size = @store.write(['Some shells for her hair.'])
      body = @store.open(key)
      assert body.respond_to? :to_path
      path = "#{@temp_dir}/#{key[0..1]}/#{key[2..-1]}"
      body.to_path.must_equal path
    end
    it 'spreads data over a 36² hash radius' do
      (<<-PROSE).each_line { |line| assert @store.write([line]).first.sha_like? }
        My wild love went riding,
        She rode all the day;
        She rode to the devil,
        And asked him to pay.

        The devil was wiser
        It's time to repent;
        He asked her to give back
        The money she spent

        My wild love went riding,
        She rode to sea;
        She gathered together
        Some shells for her hair

        She rode on to Christmas,
        She rode to the farm;
        She rode to Japan
        And re-entered a town

        My wild love is crazy
        She screams like a bird;
        She moans like a cat
        When she wants to be heard

        She rode and she rode on
        She rode for a while,
        Then stopped for an evening
        And laid her head down

        By this time the weather
        Had changed one degree,
        She asked for the people
        To let her go free

        My wild love went riding,
        She rode for an hour;
        She rode and she rested,
        And then she rode on
        My wild love went riding,
      PROSE
      subdirs = Dir["#{@temp_dir}/*"]
      subdirs.each do |subdir|
        File.basename(subdir).must_match /^[0-9a-z]{2}$/
        files = Dir["#{subdir}/*"]
        files.each do |filename|
          File.basename(filename).must_match /^[0-9a-z]{38}$/
        end
        files.length.must_be :>, 0
      end
      subdirs.length.must_equal 28
    end
  end

  need_memcached 'entity store tests' do
    describe 'MemCached' do
      before do
        @store = Rack::Cache::EntityStore::MemCached.new($memcached)
      end
      after do
        @store = nil
      end
      include RackCacheEntityStoreImplementation
    end

    describe 'options parsing' do
      before do
        uri = URI.parse("memcached://#{ENV['MEMCACHED']}/obj_ns1?show_backtraces=true")
        @memcached_metastore = Rack::Cache::MetaStore::MemCached.resolve uri
      end

      it 'passes options from uri' do
        @memcached_metastore.cache.instance_variable_get(:@options)[:show_backtraces].must_equal true
      end

      it 'takes namespace into account' do
        @memcached_metastore.cache.instance_variable_get(:@options)[:prefix_key].must_equal 'obj_ns1'
      end
    end
  end


  need_dalli 'entity store tests' do
    describe 'Dalli' do
      before do
        $dalli.flush_all
        @store = Rack::Cache::EntityStore::Dalli.new($dalli)
      end
      after do
        @store = nil
      end
      include RackCacheEntityStoreImplementation
    end

    describe 'options parsing' do
      before do
        uri = URI.parse("memcached://#{ENV['MEMCACHED']}/obj_ns1?show_backtraces=true")
        @dalli_metastore = Rack::Cache::MetaStore::Dalli.resolve uri
      end

      it 'passes options from uri' do
        @dalli_metastore.cache.instance_variable_get(:@options)[:show_backtraces].must_equal true
      end

      it 'takes namespace into account' do
        @dalli_metastore.cache.instance_variable_get(:@options)[:namespace].must_equal 'obj_ns1'
      end
    end
  end

  need_java 'entity store testing' do
    module Rack::Cache::AppEngine
      module MC
        class << (Service = {})
          def contains(key); include?(key); end
          def get(key); self[key]; end;
          def put(key, value, ttl = nil)
            self[key] = value
          end
        end

      end
    end

    describe 'GAEStore' do
      before do
        puts Rack::Cache::AppEngine::MC::Service.inspect
        @store = Rack::Cache::EntityStore::GAEStore.new
      end
      after do
        @store = nil
      end
      include RackCacheEntityStoreImplementation
    end
  end
end
