Gem::Specification.new 'rack-cache', '1.5.1' do |s|
  s.summary     = "HTTP Caching for Rack"
  s.description = "Rack::Cache is suitable as a quick drop-in component to enable HTTP caching for Rack-based applications that produce freshness (Expires, Cache-Control) and/or validation (Last-Modified, ETag) information."
  s.required_ruby_version = '>= 1.9.3'

  s.authors = ["Ryan Tomayko"]
  s.email = "r@tomayko.com"

  s.files = `git ls-files lib/ README.md MIT-LICENSE`.split("\n")
  s.extra_rdoc_files = %w[README.md MIT-LICENSE CHANGES]

  s.add_dependency 'rack', '>= 0.4'

  s.add_development_dependency 'maxitest'
  s.add_development_dependency 'memcached'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'dalli'
  s.add_development_dependency 'bump'
  s.add_development_dependency 'rake'

  s.has_rdoc = true
  s.license = "MIT"
  s.homepage = "https://github.com/rtomayko/rack-cache"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Rack::Cache", "--main", "Rack::Cache"]
end
