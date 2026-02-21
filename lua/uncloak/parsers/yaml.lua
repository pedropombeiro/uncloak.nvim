--- yaml parser — handles YAML files.
---
--- Extracts all key-value pairs from any YAML mapping, regardless of nesting
--- depth or section name.  Base64 filtering is handled by the core plugin, so
--- this parser simply yields every value it can find.

local util = require("uncloak.parsers.util")

local M = {}

--- Extract the value portion from a YAML-style line (`  KEY: value`).
---@param line string
---@return string|nil
local function extract_yaml_value(line)
  local _, value = line:match("^%s*([%w_.-]+):%s+(.+)$")
  if not value then
    return nil
  end
  return util.clean_value(value)
end

--- Scan buffer lines and return candidate values to decode.
---@param lines string[]
---@return { lnum: integer, value: string }[]
function M.extract_values(lines)
  local results = {}

  for lnum, line in ipairs(lines) do
    if not line:match("^%s*$") and not line:match("^%s*#") then
      local value = extract_yaml_value(line)
      if value then
        results[#results + 1] = { lnum = lnum, value = value }
      end
    end
  end

  return results
end

return M
