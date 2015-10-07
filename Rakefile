require 'bundler/setup'
require 'bundler/gem_tasks'
require 'rake/clean'
require 'bump/tasks'

task :default => :test

CLEAN.include %w[coverage/ doc/api tags]
CLOBBER.include %w[dist]

desc 'Run tests'
task :test do
  sh "bundle exec mtest test"
end

desc 'Generate test coverage report'
task :rcov do
  sh "rcov -I.:lib:test test/*_test.rb"
end

# DOC =======================================================================
desc 'Build all documentation'
task :doc => %w[doc:api doc:markdown]

# requires the hanna gem:
#   gem install mislav-hanna --source=http://gems.github.com
desc 'Build API documentation (doc/api)'
task 'doc:api' => 'doc/api/index.html'
file 'doc/api/index.html' => FileList['lib/**/*.rb'] do |f|
  rm_rf 'doc/api'
  sh((<<-SH).gsub(/[\s\n]+/, ' ').strip)
  hanna
    --op doc/api
    --promiscuous
    --charset utf8
    --fmt html
    --inline-source
    --line-numbers
    --accessor option_accessor=RW
    --main Rack::Cache
    --title 'Rack::Cache API Documentation'
    #{f.prerequisites.join(' ')}
  SH
end
CLEAN.include 'doc/api'

desc 'Build markdown documentation files'
task 'doc:markdown'
FileList['doc/*.markdown'].each do |source|
  dest = "doc/#{File.basename(source, '.markdown')}.html"
  file dest => [source, 'doc/layout.html.erb'] do |f|
    puts "markdown: #{source} -> #{dest}" if verbose
    require 'erb' unless defined? ERB
    require 'rdiscount' unless defined? RDiscount
    template = File.read(source)
    content = Markdown.new(ERB.new(template, 0, "%<>").result(binding), :smart).to_html
    content.match("<h1>(.*)</h1>")[1] rescue ''
    layout = ERB.new(File.read("doc/layout.html.erb"), 0, "%<>")
    output = layout.result(binding)
    File.open(dest, 'w') { |io| io.write(output) }
  end
  task 'doc:markdown' => dest
  CLEAN.include dest
end

desc 'Publish documentation'
task 'doc:publish' => :doc do
  sh 'rsync -avz doc/ gus@tomayko.com:/src/rack-cache'
end

desc 'Start the documentation development server (requires thin)'
task 'doc:server' do
  sh 'cd doc && thin --rackup server.ru --port 3035 start'
end
