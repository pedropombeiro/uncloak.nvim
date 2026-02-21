--- Hex codec for uncloak.nvim
--- Decodes hexadecimal-encoded strings (e.g. 48656c6c6f -> Hello).
--- Common for encryption keys, hashes, and binary secrets.
local util = require("uncloak.codecs.util")

local M = {
  name = "hex",
}

--- Attempt to decode a value as hex.
---@param value string The raw value to try decoding
---@param config table The plugin config (uses min_encoded_len, min_printable_ratio)
---@return string|nil decoded The decoded string, or nil if not valid hex
function M.try_decode(value, config)
  if #value < config.min_encoded_len then
    return nil
  end

  -- Must be even length (two hex chars per byte)
  if #value % 2 ~= 0 then
    return nil
  end

  -- Must be all hex characters
  if not value:match("^[0-9a-fA-F]+$") then
    return nil
  end

  -- Decode hex pairs to bytes
  local bytes = {}
  for i = 1, #value, 2 do
    local hex_pair = value:sub(i, i + 1)
    local byte = tonumber(hex_pair, 16)
    if not byte then
      return nil
    end
    bytes[#bytes + 1] = string.char(byte)
  end

  local decoded = table.concat(bytes)
  if decoded == "" then
    return nil
  end

  if not util.is_printable(decoded, config.min_printable_ratio) then
    return nil
  end

  return decoded
end

return M
