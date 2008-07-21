# Forward the request to the backend and call finish to send the
# response back upstream.
on :pass do
  debug 'pass request to backend'
  status, header, body = @backend.call(@request.env)
  @backend_response = Response.new(body, status, header)
  @response = @backend_response
  finish
end

# Called when the request is initially received.
on :receive do
  debug 'receive request'
  # pass if request.header['Cache-Control'] =~ /no-cache/
  pass unless request.method? 'GET', 'HEAD'
  pass if request.header? 'Cookie', 'Authorization', 'Expect'
  lookup
end

# Attempt to lookup the request in the cache. If a potential
# response is found, control transfers to the hit event with
# @object set to response object retrieved from cache. When
# no object is found in the cache, control transfers to miss.
on :lookup do
  debug 'lookup in cache'
  if object = @storage.get(request.fullpath)
    @object = Response.activate(object)
    if @object.fresh?
      hit
    else
      debug 'cached object found, but stale'
    end
  end
  miss
end

# The cache hit after a lookup.
on :hit do
  debug 'cache hit'
  @response = @object
  deliver
end

# Nothing was found in the cache.
on :miss do
  debug 'cache miss'
  @backend_request.header['If-Modified-Since'] = nil
  fetch
end

# Fetch the response from the backend and transfer control
# to the store event.
on :fetch do
  debug 'fetch from backend'
  status, header, body = @backend.call(@backend_request.env)
  @backend_response = Response.new(body, status, header)
  if @backend_response.cacheable?
    @response = @backend_response.dup
    @response.extend Cacheable
    store
  else
    @response = @backend_response
    deliver
  end
end

# Store the response in the cache and transfer control to
# the deliver event.
on :store do
  @object = @response
  @object.ttl = 120 if @object.ttl == 0
  debug 'store backend response in cache (TTL: %ds)', @object.ttl
  @storage.put(@request.fullpath, @object.persist)
  deliver
end

on :deliver do
  debug 'deliver response'
  finish
end


# Complete processing of the request. The backend_request,
# backend_response, and response objects should all be available
# when this event is invoked.
on :finish do
  throw :finish, @response.finish
end
