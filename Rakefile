require 'rake/clean'

task :default => :spec

CLEAN.include %w[coverage/ doc/api tags]
CLOBBER.include %w[dist]

# load gemspec like github's gem builder to surface any SAFE issues.
Thread.new do
  require 'rubygems/specification'
  $spec = eval("$SAFE=3\n#{File.read('rack-cache.gemspec')}")
end.join

# SPECS =====================================================================

desc 'Run specs with story style output'
task :spec do
  sh 'specrb --specdox -Ilib:test test/*_test.rb'
end

desc 'Run specs with unit test style output'
task :test => FileList['test/*_test.rb'] do |t|
  suite = t.prerequisites.map{|f| "-r#{f.chomp('.rb')}"}.join(' ')
  sh "ruby -Ilib:test #{suite} -e ''", :verbose => false
end

desc 'Generate test coverage report'
task :rcov do
  sh "rcov -Ilib:test test/*_test.rb"
end

# DOC =======================================================================

# requires the hanna gem:
#   gem install mislav-hanna --source=http://gems.github.com

desc 'Generate Hanna RDoc under doc/api'
task :doc => ['doc/api/index.html']

file 'doc/api/index.html' => FileList['lib/**/*.rb'] do |f|
  sh <<-SH
  hanna --charset utf8 --fmt html --inline-source --line-numbers \
    --main Rack::Cache --op doc/api \
    --title 'Rack::Cache API Documentation' \
    #{f.prerequisites.join(' ')}
  SH
end
CLEAN.include 'doc/api'

# PACKAGING =================================================================

def package(ext='')
  "dist/rack-cache-#{$spec.version}" + ext
end

desc 'Build packages'
task :package => %w[.gem .tar.gz].map {|e| package(e)}

desc 'Build and install as local gem'
task :install => package('.gem') do
  sh "gem install #{package('.gem')}"
end

directory 'dist/'

file package('.gem') => %w[dist/ rack-cache.gemspec] + $spec.files do |f|
  sh "gem build rack-cache.gemspec"
  mv File.basename(f.name), f.name
end

file package('.tar.gz') => %w[dist/] + $spec.files do |f|
  sh "git archive --format=tar HEAD | gzip > #{f.name}"
end

# GEMSPEC ===================================================================

file 'rack-cache.gemspec' => FileList['{lib,test}/**','Rakefile'] do |f|
  # read spec file and split out manifest section
  spec = File.read(f.name)
  parts = spec.split("  # = MANIFEST =\n")
  fail 'bad spec' if parts.length != 3
  # determine file list from git ls-files
  files = `git ls-files`.
    split("\n").sort.reject{ |file| file =~ /^\./ }.
    map{ |file| "    #{file}" }.join("\n")
  # piece file back together and write...
  parts[1] = "  s.files = %w[\n#{files}\n  ]\n"
  spec = parts.join("  # = MANIFEST =\n")
  spec.sub!(/s.date = '.*'/, "s.date = '#{Time.now.strftime("%Y-%m-%d")}'")
  File.open(f.name, 'w') { |io| io.write(spec) }
  puts "updated #{f.name}"
end
