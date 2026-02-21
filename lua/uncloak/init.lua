local M = {}

--- Default configuration.
local defaults = {
  --- Whether the plugin is globally enabled.
  enabled = true,
  --- Text shown before the decoded value.
  --- Can be a plain string (e.g. " ⮕ ") or a table { icon = "…", hl = "…" }.
  --- When nvim-web-devicons is available, the default is the unlock icon
  --- with its highlight; otherwise falls back to " ⮕ ".
  prefix = nil,
  --- Highlight group for the prefix (used when `prefix` is a plain string).
  hl_group_prefix = "UncloakPrefix",
  --- Highlight group for normal decoded values.
  hl_group_value = "UncloakValue",
  --- Highlight group for suspicious decoded values.
  hl_group_warn = "UncloakWarn",
  --- Maximum display length for decoded text (longer values are truncated).
  max_len = 120,
  --- Ignore base64 values shorter than this (reduces false positives).
  min_encoded_len = 8,
  --- Decoded content must be at least this ratio of printable ASCII.
  min_printable_ratio = 0.75,
  --- Debounce interval in milliseconds for re-rendering.
  debounce_ms = 150,
  --- Map of filetype → parser name.
  --- Each parser's optional `detect()` method provides filename-based
  --- detection as a fallback when a filetype is not in this map.
  ---
  --- Example:
  ---   filetypes = { helm = "yaml", dotenv = "sh", custom_toml = "toml" }
  filetypes = {
    dotenv = "sh",
    conf = "sh",
    sh = "sh",
    toml = "toml",
    yaml = "yaml",
  },
  --- Custom parser modules to register.
  --- Keys are parser names, values are parser tables with an
  --- `extract_values(lines)` function and an optional `detect(bufnr)` function.
  ---
  --- Example — reuse the built-in YAML parser for Helm files:
  ---   parsers = {
  ---     helm = require("uncloak.parsers.yaml"),
  ---   },
  ---
  --- Example — define a fully custom parser:
  ---   parsers = {
  ---     my_format = {
  ---       detect = function(bufnr) return vim.fn.expand("%:t") == "my.conf" end,
  ---       extract_values = function(lines)
  ---         local results = {}
  ---         for i, line in ipairs(lines) do
  ---           local val = line:match("^SECRET:%s*(.+)$")
  ---           if val then results[#results + 1] = { lnum = i, value = val } end
  ---         end
  ---         return results
  ---       end,
  ---     },
  ---   },
  parsers = {},
}

local ns = vim.api.nvim_create_namespace("uncloak")
local scheduled = {}

--- Parser registry — maps parser name → parser module.
--- Built-in parsers are registered in setup(); users can add more via
--- `require("uncloak").register_parser()`.
---@type table<string, { detect: fun(bufnr: integer): boolean, extract_values: fun(lines: string[]): { lnum: integer, value: string }[] }>
local parsers = {}

-- ---------------------------------------------------------------------------
-- Parser registry API
-- ---------------------------------------------------------------------------

--- Register a parser module under the given name.
---
--- A parser must be a table with two functions:
---   detect(bufnr: integer) -> boolean
---     Return true if this parser should handle the buffer (filename-based).
---   extract_values(lines: string[]) -> { lnum: integer, value: string }[]
---     Return line numbers and raw values to check for base64.
---
--- Users can map filetypes to this parser by adding entries to `opts.filetypes`
--- in `setup()`, or by calling this function and updating the mapping:
---
---   local uncloak = require("uncloak")
---   uncloak.register_parser("yaml", my_custom_yaml_parser)
---   -- or reuse the built-in yaml parser for a new filetype:
---   uncloak.config.filetypes["helm"] = "yaml"
---
---@param name string  parser identifier (e.g. "sh", "yaml", "toml")
---@param parser table parser module conforming to the contract above
function M.register_parser(name, parser)
  vim.validate({
    name = { name, "string" },
    parser = { parser, "table" },
    extract_values = { parser.extract_values, "function" },
  })
  if parser.detect then
    vim.validate({ detect = { parser.detect, "function" } })
  end
  parsers[name] = parser
end

--- Return a copy of the parser registry (for introspection).
---@return table<string, table>
function M.get_parsers()
  return vim.tbl_extend("error", {}, parsers)
end

-- ---------------------------------------------------------------------------
-- Validation helpers
-- ---------------------------------------------------------------------------

--- Strict base64 validation (standard alphabet, no URL-safe).
---@param value string
---@return boolean
local function is_base64(value)
  if value == "" or #value < M.config.min_encoded_len then
    return false
  end
  if #value % 4 ~= 0 then
    return false
  end
  local stripped = value:gsub("=+$", "")
  if stripped == "" then
    return false
  end
  local pad = #value - #stripped
  if pad > 2 then
    return false
  end
  return stripped:match("^[A-Za-z0-9+/]+$") ~= nil
end

--- Return true when the decoded bytes are mostly human-readable text.
---@param decoded string
---@return boolean
local function is_printable(decoded)
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
  return (printable / #decoded) >= M.config.min_printable_ratio
end

--- Safely decode a base64 string, returning nil on failure.
---@param value string
---@return string|nil
local function decode_base64(value)
  local ok, decoded = pcall(vim.base64.decode, value)
  if not ok then
    return nil
  end
  return decoded
end

-- ---------------------------------------------------------------------------
-- Display helpers
-- ---------------------------------------------------------------------------

--- Replace non-printable bytes with visible escape sequences.
---@param decoded string
---@return string
local function sanitize(decoded)
  local parts = {}
  for i = 1, #decoded do
    local byte = decoded:byte(i)
    if byte >= 32 and byte <= 126 then
      parts[#parts + 1] = string.char(byte)
    elseif byte == 9 then
      parts[#parts + 1] = "\\t"
    elseif byte == 10 then
      parts[#parts + 1] = "\\n"
    elseif byte == 13 then
      parts[#parts + 1] = "\\r"
    else
      parts[#parts + 1] = string.format("\\x%02X", byte)
    end
  end
  return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- Suspicious content detection
-- ---------------------------------------------------------------------------

local suspicious_patterns = {
  -- Shell / system commands
  "curl%s",
  "wget%s",
  "rm%s",
  "eval%s",
  "exec%s",
  "bash%s",
  "/bin/sh",
  "|%s*sh",
  "python%s",
  "nc%s",
  "ncat%s",
  "xargs%s",
  "chmod%s",
  "base64%s",
  -- Shell metacharacters
  "<%(",     -- process substitution
  "$%(.*%)", -- command substitution
  "`.*`",    -- backtick substitution
}

--- Return true when the raw decoded content looks suspicious.
---@param decoded string
---@return boolean
local function is_suspicious(decoded)
  local lower = decoded:lower()
  for _, pat in ipairs(suspicious_patterns) do
    if lower:match(pat) then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Parser resolution
-- ---------------------------------------------------------------------------

--- Resolve which parser should handle the given buffer.
--- First checks filetype → parser name mapping, then falls back to each
--- parser's `detect()` method for filename-based matching.
---@param bufnr integer
---@return table|nil  parser module, or nil if no parser matches
local function resolve_parser(bufnr)
  -- 1. Try filetype mapping.
  local ft = vim.bo[bufnr].filetype
  local parser_name = M.config.filetypes[ft]
  if parser_name and parsers[parser_name] then
    return parsers[parser_name]
  end

  -- 2. Fall back to filename-based detection.
  for _, parser in pairs(parsers) do
    if parser.detect and parser.detect(bufnr) then
      return parser
    end
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Decorate a single buffer with decoded base64 virtual text.
---@param bufnr integer
local function render(bufnr)
  if not M.config or not M.config.enabled then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return
  end
  if vim.b[bufnr].uncloak_enabled == false then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    return
  end

  local parser = resolve_parser(bufnr)
  if not parser then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local candidates = parser.extract_values(lines)
  for _, candidate in ipairs(candidates) do
    local value = candidate.value
    if is_base64(value) then
      local decoded = decode_base64(value)
      if decoded and decoded ~= "" and is_printable(decoded) then
        local display = sanitize(decoded)
        if #display > M.config.max_len then
          display = display:sub(1, M.config.max_len - 3) .. "..."
        end

        local value_hl = is_suspicious(decoded) and M.config.hl_group_warn or M.config.hl_group_value

        vim.api.nvim_buf_set_extmark(bufnr, ns, candidate.lnum - 1, 0, {
          virt_text = {
            { M._prefix_text or " ⮕ ", M._prefix_hl or M.config.hl_group_prefix },
            { display, value_hl },
          },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

--- Schedule a debounced render for the given buffer.
---@param bufnr? integer defaults to current buffer
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if scheduled[bufnr] then
    return
  end
  scheduled[bufnr] = true

  vim.defer_fn(function()
    scheduled[bufnr] = nil
    render(bufnr)
  end, M.config and M.config.debounce_ms or 150)
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

local function setup_highlights()
  vim.api.nvim_set_hl(0, "UncloakPrefix", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "UncloakValue", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "UncloakWarn", { link = "DiagnosticWarn", default = true })
end

local function create_autocmds()
  local group = vim.api.nvim_create_augroup("Uncloak", { clear = true })
  vim.api.nvim_create_autocmd(
    { "BufEnter", "BufReadPost", "BufWritePost", "FileType", "TextChanged", "TextChangedI" },
    {
      group = group,
      callback = function(args)
        M.refresh(args.buf)
      end,
    }
  )
end

local function register_builtin_parsers()
  local builtins = { "sh", "toml", "yaml" }
  for _, name in ipairs(builtins) do
    if not parsers[name] then
      parsers[name] = require("uncloak.parsers." .. name)
    end
  end
end

--- Resolve the prefix into a { text, hl } pair for use in virt_text.
--- Supports: nil (auto-detect), plain string, or { icon = "…", hl = "…" } table.
---@return string prefix_text
---@return string prefix_hl
local function resolve_prefix(config)
  local prefix = config.prefix

  -- Table form: { icon = "…", hl = "…" }
  if type(prefix) == "table" then
    return (prefix.icon or "") .. " ", prefix.hl or config.hl_group_prefix
  end

  -- Explicit string: use as-is with the configured prefix highlight.
  if type(prefix) == "string" then
    return prefix, config.hl_group_prefix
  end

  -- nil: auto-detect from nvim-web-devicons, fall back to plain text.
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local unlock = "" -- nf-fa-unlock (U+F09C)
    local _, color, cterm = devicons.get_icon_colors("lock", nil, { default = false })
    devicons.set_icon({
      uncloak = {
        icon = unlock,
        color = color,
        cterm_color = cterm,
        name = "Uncloak",
      },
    })

    local icon, hl = devicons.get_icon("uncloak", nil, { default = false })
    if icon then
      return " " .. icon .. " ", hl
    end
  end

  return " ⮕ ", config.hl_group_prefix
end

--- Initialise the plugin.  Called automatically by lazy.nvim when `opts` is
--- set, or manually via `require("uncloak").setup(opts)`.
---
--- @param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  -- Resolve the prefix into concrete text + highlight.
  M._prefix_text, M._prefix_hl = resolve_prefix(M.config)

  -- Register user-supplied parsers first (they take precedence over builtins).
  for name, parser in pairs(M.config.parsers) do
    M.register_parser(name, parser)
  end

  register_builtin_parsers()
  setup_highlights()
  create_autocmds()

  -- Register the toggle command exactly once.
  if not M._command_registered then
    vim.api.nvim_create_user_command("UncloakToggle", function()
      local bufnr = vim.api.nvim_get_current_buf()
      local current = vim.b[bufnr].uncloak_enabled
      if current == nil then
        current = true
      end
      vim.b[bufnr].uncloak_enabled = not current
      render(bufnr)
    end, { desc = "Toggle uncloak virtual text for the current buffer" })
    M._command_registered = true
  end

  -- Render any already-loaded buffers immediately.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      render(bufnr)
    end
  end

  return M
end

return M
