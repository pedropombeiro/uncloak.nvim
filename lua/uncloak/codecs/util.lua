--- Shared utilities for uncloak codec modules.
local M = {}

--- Check if a decoded string is mostly printable ASCII.
--- Used to filter out false positives where valid-looking encoded data
--- decodes to binary garbage.
---@param decoded string
---@param min_ratio number Minimum ratio of printable bytes (0.0 - 1.0)
---@return boolean
function M.is_printable(decoded, min_ratio)
  if decoded == "" then
    return false
  end

  local printable = 0
  for i = 1, #decoded do
    local byte = decoded:byte(i)
    if (byte >= 32 and byte <= 126) or byte == 9 or byte == 10 or byte == 13 then
      printable = printable + 1
    end
  end

  return (printable / #decoded) >= min_ratio
end

return M
