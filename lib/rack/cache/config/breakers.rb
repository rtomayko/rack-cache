# Adds a very long max-age response header when the requested url
# looks like it includes a cache busting timestamp. Cache busting
# URLs look like this:
#   http://HOST/PATH?DIGITS
#
# DIGITS is typically the number of seconds since some epoch but
# this can theoretically be any set of digits. Example:
#   http://example.com/css/foo.css?7894387283
#
on :fetch do
  next if response.freshness_information?
  if request.url =~ /\?\d+$/
    debug 'adding huge max-age to response for cache breaking URL'
    response.ttl = 100000000000000
  end
end
