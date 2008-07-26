# Forward the request to the backend and call finish to send the
# response back upstream.
on :pass do
  debug 'pass request to backend'
  @backend_request = @request
  @backend_response = Response.new(*@backend.call(@request.env))
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
  # TODO extract code that builds request to forward
  environment = @request.env.dup
  environment.delete('If-Modified-Since')
  @backend_request = Request.new(environment)
  fetch
end

# Fetch the response from the backend and transfer control
# to the store event.
on :fetch do
  debug 'fetch from backend'
  @backend_response = Response.new(*@backend.call(@backend_request.env))
  if @backend_response.cacheable?
    @response = @backend_response.dup
    store
  else
    debug "response isn't cacheable ..."
    @response = @backend_response
    deliver
  end
end

# Store the response in the cache and transfer control to
# the deliver event.
on :store do
  @object = @response.cache
  @object.ttl = default_ttl if @object.ttl.nil?
  debug 'store backend response in cache (TTL: %ds)', @object.ttl
  @storage.put(@request.fullpath, object.to_a)
  @response = @object
  deliver
end

on :deliver do
  # Handle conditional GET w/ If-Modified-Since
  if @response.last_modified_at?(@request.header['If-Modified-Since'])
    debug 'upstream version is unmodified; sending 304'
    response.status = 304
    response.body = ''
  end
  debug 'deliver response'
  finish
end


# Complete processing of the request. The backend_request,
# backend_response, and response objects should all be available
# when this event is invoked.
on :finish do
  throw :finish, @response.to_a
end
