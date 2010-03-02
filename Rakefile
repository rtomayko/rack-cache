task :default => :build

task :build do |t|
  cp_r FileList['doc/*.{html,css}'], '.'
  cp_r 'doc/api', '.'
end
