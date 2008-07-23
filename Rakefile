task :default => :test

desc 'Run specs with unit test style output'
task :test do
  sh 'testrb -Ilib:test test/*_test.rb'
end

desc 'Run specs with story style output'
task :spec do
  sh 'specrb --specdox -Ilib:test test/*_test.rb'
end
