# Adds a max-age header to 

on :store do
  next if @response.freshness_information?
  if @request.url =~ /\?\d+$/
    debug 'adding expires headers to cache breaking URL'
    @response.ttl = 100000000000000
  end
end
