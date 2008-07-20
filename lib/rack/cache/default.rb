# Forward the request to the backend and call finish to send the
# response back upstream.
on :pass do
  status, header, body = @backend.call(@request.env)
  @backend_response = Response.new(body, status, header)
  @response = @backend_response
  finish
end

# Called when the request is initially received.
on :receive do
  # TODO actual Cache-Control parsing
  pass if request.header['Cache-Control'] =~ /no-cache/
  pass unless request.method? 'GET', 'HEAD'
  pass if request.header? 'Cookie', 'Authorization', 'Expect'
  lookup
end

# Attempt to lookup the request in the cache. If a potential
# response is found, control transfers to the hit event with
# @object set to response object retrieved from cache. When
# no object is found in the cache, control transfers to miss.
on :lookup do
  if object = @storage.get(request.url)
    @object = Response.activate(object)
    hit if @object.fresh?
  end
  miss
end

# The cache hit after a lookup.
on :hit do
  @response = @object
  deliver
end

# Nothing was found in the cache.
on :miss do
  fetch
end

# Fetch the response from the backend and transfer control
# to the store event.
on :fetch do
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
  @storage.put(@request.url, @object.persist)
  deliver
end

on :deliver do
  finish
end


# Complete processing of the request. The backend_request,
# backend_response, and response objects should all be available
# when this event is invoked.
on :finish do
  throw :finish, @response.finish
end
