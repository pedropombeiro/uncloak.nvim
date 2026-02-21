--- sh parser — handles shell-style KEY=VALUE files (.env, .env.*, conf, sh).
---
--- This parser treats every line as a potential key-value pair.
--- No section scoping is applied.

local util = require("uncloak.parsers.util")

local M = {}

--- Detect whether this parser should handle the given buffer.
--- Returns true for .env / .env.* filenames regardless of filetype.
---@param bufnr integer
---@return boolean
function M.detect(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end
  local basename = vim.fn.fnamemodify(name, ":t")
  return basename == ".env" or basename:match("^%.env%.") ~= nil
end

--- Extract the value portion from an env-style line (`KEY=VALUE`).
--- Handles `export` prefix, single/double quoting, and inline comments.
---@param line string
---@return string|nil
local function extract_env_value(line)
  local _, value = line:match("^%s*export%s+([%w_.-]+)%s*=%s*(.+)$")
  if not value then
    _, value = line:match("^%s*([%w_.-]+)%s*=%s*(.+)$")
  end
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
    local value = extract_env_value(line)
    if value then
      results[#results + 1] = { lnum = lnum, value = value }
    end
  end
  return results
end

return M
