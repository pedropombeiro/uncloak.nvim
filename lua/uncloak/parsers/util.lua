--- Shared utilities for uncloak parsers.

local M = {}

--- Strip surrounding quotes and inline comments from a raw value string.
---@param value string
---@return string|nil
function M.clean_value(value)
  local quote = value:sub(1, 1)
  if quote == "'" or quote == '"' then
    if value:sub(-1) == quote and #value >= 2 then
      return value:sub(2, -2)
    end
    return nil -- unterminated quote
  end

  -- Unquoted: strip inline comments and trailing whitespace.
  value = value:gsub("%s+#.*$", "")
  value = value:gsub("%s+$", "")
  if value == "" then
    return nil
  end
  return value
end

return M
