# uncloak.nvim

Reveal base64-encoded values hiding in your config files as inline virtual
text — right inside Neovim.  Spot suspicious payloads, obfuscated credentials,
or hidden shell commands at a glance.

## Features

- Inline decoded virtual text at end of line
- Suspicious content highlighted with a warning colour (shell commands, URLs, …)
- Built-in parsers for:
  - **sh** — `.env`, `.env.*`, and generic `KEY=VALUE` / shell-style files
  - **toml** — mise config (`mise.toml`, `.mise.toml`, `.mise.*.toml`), scoped to `[env]` sections
  - **yaml** — any YAML file (e.g. docker-compose, Kubernetes manifests)
- **Extensible** — map new filetypes to existing parsers, or register custom parsers, all from `opts`
- Per-buffer toggle via `:UncloakToggle`
- Debounced updates on every text change

## Requirements

- Neovim **0.11+** (uses `vim.base64.decode`)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional, for icon prefix)

## Installation

### lazy.nvim

```lua
{
  "pedropombeiro/uncloak.nvim",
  ft = { "dotenv", "conf", "toml", "yaml" },
  event = { "BufReadPost .env", "BufReadPost .env.*" },
  opts = {},
}
```

> **Why `event`?** Files like `.env` are often detected as filetype `sh` by
> Neovim. The `BufReadPost` patterns ensure uncloak loads for these files
> regardless of their detected filetype, while the built-in `sh` parser's
> `detect()` method handles the rest.

## Configuration

All options with their defaults:

```lua
require("uncloak").setup({
  enabled = true,

  -- Prefix shown before the decoded value.
  -- nil          → auto-detect: uses nvim-web-devicons unlock icon, or " ⮕ " as fallback
  -- "string"     → use this literal string
  -- { icon, hl } → use icon with a custom highlight group
  prefix = nil,

  -- Prefix shown before suspicious decoded values (same format as prefix).
  -- nil → falls back to `prefix`
  warn_prefix = nil,

  -- Sign column text for decoded values (max 2 chars, or "" to disable).
  sign = "",
  -- Sign column text for suspicious decoded values (or "" to disable).
  warn_sign = "",

  highlights = {
    prefix     = "UncloakPrefix",     -- links to DiagnosticVirtualTextInfo
    warn_prefix = "UncloakWarnPrefix", -- links to DiagnosticVirtualTextWarn
    value      = "UncloakValue",      -- links to DiagnosticVirtualTextInfo
    warn       = "UncloakWarn",       -- links to DiagnosticVirtualTextWarn
    sign_value = "UncloakSignValue",  -- links to DiagnosticInfo
    sign_warn  = "UncloakSignWarn",   -- links to DiagnosticWarn
  },
  max_len = 120,
  min_encoded_len = 8,
  min_printable_ratio = 0.75,
  debounce_ms = 150,

  -- Map filetypes to built-in parser names.
  filetypes = {
    dotenv = "sh",
    conf   = "sh",
    sh     = "sh",
    toml   = "toml",
    yaml   = "yaml",
  },

  -- Register custom parsers (see "Extending" below).
  parsers = {},
})
```

## Extending

### Map a new filetype to an existing parser

If your filetype is YAML-based but detected as something other than `yaml`,
just add it to the `filetypes` map:

```lua
opts = {
  filetypes = {
    -- These are merged with the defaults.
    helm = "yaml",
    ["yaml.docker-compose"] = "yaml",
    eruby = "sh",
  },
}
```

### Register a custom parser via `opts`

Custom parsers can be defined entirely in `opts.parsers`. A parser is a table
with:

| Field | Type | Required | Description |
|---|---|---|---|
| `extract_values(lines)` | `fun(string[]): {lnum: integer, value: string}[]` | ✅ | Return 1-indexed line numbers and raw values to check for base64 |
| `detect(bufnr)` | `fun(integer): boolean` | ❌ | Filename-based fallback detection (used when no filetype mapping matches) |

#### Example: reuse the built-in YAML parser for Helm charts

```lua
opts = {
  filetypes = { helm = "yaml" },
}
```

Since the built-in `yaml` parser already handles all YAML key-value pairs, you
only need to map the filetype. No custom parser required.

#### Example: register a new parser for a custom format

```lua
local util = require("uncloak.parsers.util")

opts = {
  filetypes = { ini = "ini" },
  parsers = {
    ini = {
      detect = function(bufnr)
        return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e") == "ini"
      end,
      extract_values = function(lines)
        local results = {}
        for lnum, line in ipairs(lines) do
          local _, value = line:match("^%s*([%w_]+)%s*=%s*(.+)$")
          if value then
            results[#results + 1] = { lnum = lnum, value = util.clean_value(value) }
          end
        end
        return results
      end,
    },
  },
}
```

### Programmatic API

For dynamic use (e.g. from another plugin), methods are also available:

```lua
local uncloak = require("uncloak")

-- Register a parser at runtime.
uncloak.register_parser("my_format", {
  extract_values = function(lines) ... end,
  detect = function(bufnr) ... end,  -- optional
})

-- Map a filetype to it.
uncloak.config.filetypes["my_ft"] = "my_format"

-- List all registered parsers:
vim.print(uncloak.get_parsers())
```

## Commands

| Command | Description |
|---|---|
| `:UncloakToggle` | Toggle virtual text for the current buffer |

## How it works

1. On `BufEnter`, `TextChanged`, and other events, the plugin resolves a
   parser for the buffer — first by filetype mapping, then by each parser's
   `detect()` method.
2. The parser's `extract_values()` scans the buffer lines and returns
   candidate key-value pairs (with section scoping for TOML `[env]` blocks).
3. Values are validated as strict base64 (correct length, charset, padding).
4. Decoded bytes are checked for printability to filter false positives.
5. Surviving values are sanitised and displayed as end-of-line virtual text.
6. Suspicious content (shell commands, URLs, …) is highlighted with
    `UncloakWarn`.

## Examples

Test files are provided in the [`examples/`](examples/) directory:

- [`examples/.env.example`](examples/.env.example) — dotenv file with normal values, harmless base64, and suspicious payloads
- [`examples/mise.toml`](examples/mise.toml) — mise config with `[env]` section containing base64 values
- [`examples/docker-compose.example.yaml`](examples/docker-compose.example.yaml) — docker-compose with `env:` blocks

## License

MIT
