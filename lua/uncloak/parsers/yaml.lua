--- yaml parser — handles YAML files with `env:` mapping blocks.
---
--- Only key-value pairs nested directly under an `env:` key (at any nesting
--- depth) are inspected.  For example, both top-level `env:` and
--- `services.web.env:` are recognised.

local util = require("uncloak.parsers.util")

local M = {}

--- Extract the value portion from a YAML-style line (`  KEY: value`).
---@param line string
---@return string|nil
local function extract_yaml_value(line)
  local _, value = line:match("^%s+([%w_.-]+):%s+(.+)$")
  if not value then
    return nil
  end
  return util.clean_value(value)
end

--- Scan buffer lines and return candidate values to decode.
--- Only values inside `env:` mapping blocks are returned.
---@param lines string[]
---@return { lnum: integer, value: string }[]
function M.extract_values(lines)
  local results = {}
  local in_env_section = false
  local env_indent = nil

  for lnum, line in ipairs(lines) do
    -- Skip blank lines and comments — they don't change section state.
    if not line:match("^%s*$") and not line:match("^%s*#") then
      local indent = #(line:match("^(%s*)") or "")

      if line:match("^%s*env%s*:") then
        -- Found an `env:` key at some nesting level.
        in_env_section = true
        env_indent = indent
      elseif in_env_section and env_indent then
        if indent <= env_indent then
          -- Exited the `env:` block (same or lesser indentation).
          in_env_section = false
          env_indent = nil
        end
      end

      if in_env_section and env_indent and indent > env_indent then
        local value = extract_yaml_value(line)
        if value then
          results[#results + 1] = { lnum = lnum, value = value }
        end
      end
    end
  end

  return results
end

return M
