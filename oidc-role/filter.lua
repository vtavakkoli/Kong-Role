local M = {}

local function matches(uri, pattern)
  if type(pattern) ~= "string" or pattern == "" then
    return false
  end

  local ok, start_index = pcall(string.find, uri or "", pattern)
  if not ok then
    if kong and kong.log and kong.log.warn then
      kong.log.warn("oidc-role ignored invalid request filter pattern: ", pattern)
    end
    return false
  end

  return start_index ~= nil
end

local function should_ignore_request(patterns)
  for _, pattern in ipairs(patterns or {}) do
    if matches(ngx.var.uri, pattern) then
      return true
    end
  end
  return false
end

function M.shouldProcessRequest(config)
  return not should_ignore_request(config.filters)
end

return M
