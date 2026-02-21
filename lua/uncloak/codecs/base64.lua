--- Base64 codec for uncloak.nvim
--- Decodes standard base64 (RFC 4648 §4): A-Za-z0-9+/ with = padding.
local util = require("uncloak.codecs.util")

local M = {
  name = "base64",
}

--- Attempt to decode a value as standard base64.
---@param value string The raw value to try decoding
---@param config table The plugin config (uses min_encoded_len, min_printable_ratio)
---@return string|nil decoded The decoded string, or nil if not valid base64
function M.try_decode(value, config)
  if #value < config.min_encoded_len then
    return nil
  end

  if #value % 4 ~= 0 then
    return nil
  end

  -- Strip and validate padding (max 2 trailing '=')
  local padding = value:match("(=+)$")
  if padding and #padding > 2 then
    return nil
  end

  local body = padding and value:sub(1, -(#padding + 1)) or value
  if not body:match("^[A-Za-z0-9+/]+$") then
    return nil
  end

  local ok, decoded = pcall(vim.base64.decode, value)
  if not ok or not decoded or decoded == "" then
    return nil
  end

  if not util.is_printable(decoded, config.min_printable_ratio) then
    return nil
  end

  return decoded
end

return M
