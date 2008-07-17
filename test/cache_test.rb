require "#{File.dirname(__FILE__)}/spec_setup"

describe 'Rack::Cache' do

  it 'should autoload the Request class' do
    Rack::Cache::Request.should.be.kind_of Class
  end

  it 'should autoload the Response class' do
    Rack::Cache::Response.should.be.kind_of Class
  end

  it 'should autoload the Language module' do
    Rack::Cache::Language.should.be.kind_of Module
  end

  it 'should autoload the Storage module' do
    Rack::Cache::Storage.should.be.kind_of Module
  end

end
