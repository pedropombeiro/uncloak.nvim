--- toml parser — handles mise config files (mise.toml, .mise.toml, .mise.*.toml).
---
--- Only lines inside an `[env]` TOML section are inspected.
--- Key-value pairs use the same `KEY = VALUE` syntax as env files.

local util = require("uncloak.parsers.util")

local M = {}

--- Detect whether this parser should handle the given buffer.
--- Returns true for mise TOML config filenames.
---@param bufnr integer
---@return boolean
function M.detect(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end
  local basename = vim.fn.fnamemodify(name, ":t")
  return basename == "mise.toml"
    or basename == ".mise.toml"
    or basename:match("^%.?mise%..+%.toml$") ~= nil
end

--- Extract a key-value pair from a TOML-style line (`KEY = VALUE`).
---@param line string
---@return string|nil
local function extract_toml_value(line)
  local _, value = line:match("^%s*([%w_.-]+)%s*=%s*(.+)$")
  if not value then
    return nil
  end
  return util.clean_value(value)
end

--- Scan buffer lines and return candidate values to decode.
--- Only values inside `[env]` sections are returned.
---@param lines string[]
---@return { lnum: integer, value: string }[]
function M.extract_values(lines)
  local results = {}
  local in_env_section = false

  for lnum, line in ipairs(lines) do
    -- Detect section headers like `[env]`, `[tools]`, etc.
    local section = line:match("^%s*%[([%w_]+)%]%s*$")
    if section then
      in_env_section = (section == "env")
    elseif in_env_section then
      local value = extract_toml_value(line)
      if value then
        results[#results + 1] = { lnum = lnum, value = value }
      end
    end
  end

  return results
end

return M
