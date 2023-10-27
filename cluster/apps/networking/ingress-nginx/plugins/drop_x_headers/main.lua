local ngx = ngx

local _M = {}

-- Do not working with proxy_set_header sadly

function _M.rewrite()
  if not ngx.var.dropXHeaders then
    return
  end

  -- Drop headers
  ngx.req.set_header("X-Request-ID", "")
  ngx.req.set_header("X-Real-IP", "")
  ngx.req.set_header("X-Forwarded-For", "")
  ngx.req.set_header("X-Forwarded-Host", "")
  ngx.req.set_header("X-Forwarded-Port", "")
  ngx.req.set_header("X-Forwarded-Proto", "")
  ngx.req.set_header("X-Forwarded-Scheme", "")
  ngx.req.set_header("X-Original-URI", "")
  ngx.req.set_header("X-Scheme", "")
  ngx.req.set_header("X-Original-Forwarded-For", "")
end

return _M
