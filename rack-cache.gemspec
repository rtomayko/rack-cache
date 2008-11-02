Gem::Specification.new do |s|
  s.specification_version = 2 if s.respond_to? :specification_version=
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=

  s.name = 'rack-cache'
  s.version = '0.2.0'
  s.date = '2008-10-24'

  s.description = "HTTP Caching for Rack"
  s.summary     = "HTTP Caching for Rack"

  s.authors = ["Ryan Tomayko"]
  s.email = "r@tomayko.com"

  # = MANIFEST =
  s.files = %w[
    CHANGES
    COPYING
    README
    Rakefile
    TODO
    doc/configuration.markdown
    doc/events.dot
    doc/faq.markdown
    doc/index.markdown
    doc/layout.html.erb
    doc/license.markdown
    doc/rack-cache.css
    doc/storage.markdown
    lib/rack/cache.rb
    lib/rack/cache/config.rb
    lib/rack/cache/config/busters.rb
    lib/rack/cache/config/default.rb
    lib/rack/cache/config/no-cache.rb
    lib/rack/cache/context.rb
    lib/rack/cache/core.rb
    lib/rack/cache/entitystore.rb
    lib/rack/cache/headers.rb
    lib/rack/cache/metastore.rb
    lib/rack/cache/options.rb
    lib/rack/cache/request.rb
    lib/rack/cache/response.rb
    lib/rack/cache/storage.rb
    lib/rack/utils/environment_headers.rb
    rack-cache.gemspec
    test/cache_test.rb
    test/config_test.rb
    test/context_test.rb
    test/core_test.rb
    test/entitystore_test.rb
    test/environment_headers_test.rb
    test/headers_test.rb
    test/logging_test.rb
    test/metastore_test.rb
    test/options_test.rb
    test/pony.jpg
    test/response_test.rb
    test/spec_setup.rb
    test/storage_test.rb
  ]
  # = MANIFEST =

  s.test_files = s.files.select {|path| path =~ /^test\/.*_test.rb/}

  s.extra_rdoc_files = %w[README COPYING TODO CHANGES]
  s.add_dependency 'rack', '~> 0.4'

  s.has_rdoc = true
  s.homepage = "http://tomayko.com/src/rack-cache/"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Rack::Cache", "--main", "Rack::Cache"]
  s.require_paths = %w[lib]
  s.rubyforge_project = 'wink'
  s.rubygems_version = '1.1.1'
end
