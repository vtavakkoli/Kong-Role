local M = {}

function M.configure(config)
  if not config.session_secret then
    return true
  end

  local decoded_session_secret = ngx.decode_base64(config.session_secret)
  if not decoded_session_secret or decoded_session_secret == "" then
    kong.log.err("Invalid plugin configuration: session secret could not be decoded")
    return nil, "invalid session secret"
  end

  ngx.var.session_secret = decoded_session_secret
  return true
end

return M
