--- Base64url codec for uncloak.nvim
--- Decodes URL-safe base64 (RFC 4648 §5): A-Za-z0-9-_ with optional = padding.
--- Common in JWTs, cloud API tokens, and URL-embedded secrets.
local util = require("uncloak.codecs.util")

local M = {
  name = "base64url",
}

--- Attempt to decode a value as base64url.
---@param value string The raw value to try decoding
---@param config table The plugin config (uses min_encoded_len, min_printable_ratio)
---@return string|nil decoded The decoded string, or nil if not valid base64url
function M.try_decode(value, config)
  if #value < config.min_encoded_len then
    return nil
  end

  -- Strip and validate optional padding
  local padding = value:match("(=+)$")
  if padding and #padding > 2 then
    return nil
  end

  local body = padding and value:sub(1, -(#padding + 1)) or value

  -- Accept A-Za-z0-9 plus optional - and _ (URL-safe chars).
  -- Values without - or _ are still valid base64url (RFC 4648 §5 says padding is optional).
  -- The standard base64 codec runs first and rejects unpadded values, so we catch the rest.
  if not body:match("^[A-Za-z0-9%-_]+$") then
    return nil
  end

  -- Convert base64url to standard base64 for decoding
  local standard = body:gsub("%-", "+"):gsub("_", "/")

  -- Add padding to make length divisible by 4
  local pad_needed = (4 - #standard % 4) % 4
  standard = standard .. string.rep("=", pad_needed)

  local ok, decoded = pcall(vim.base64.decode, standard)
  if not ok or not decoded or decoded == "" then
    return nil
  end

  if not util.is_printable(decoded, config.min_printable_ratio) then
    return nil
  end

  return decoded
end

return M
