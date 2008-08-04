# Adds a max-age header to 

on :store do
  next if object.freshness_information?
  if request.url =~ /\?\d+$/
    debug 'adding expires headers to cache breaking URL'
    object.ttl = 100000000000000
  end
end
