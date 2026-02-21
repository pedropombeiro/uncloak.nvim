# uncloak.nvim

Reveal base64-encoded values hiding in your config files as inline virtual
text — right inside Neovim.  Spot suspicious payloads, obfuscated credentials,
or hidden shell commands at a glance.

## Features

- Inline decoded virtual text at end of line
- Suspicious content highlighted with a warning colour (shell commands, URLs, …)
- Built-in parsers for:
  - **env** — `.env`, `.env.*`, and generic `KEY=VALUE` files
  - **toml** — mise config (`mise.toml`, `.mise.toml`, `.mise.*.toml`), scoped to `[env]` sections
  - **yaml** — YAML files with `env:` mapping blocks (e.g. docker-compose), at any nesting depth
- **Extensible** — map new filetypes to existing parsers, or register custom parsers, all from `opts`
- Per-buffer toggle via `:UncloakToggle`
- Debounced updates on every text change

## Requirements

- Neovim **0.11+** (uses `vim.base64.decode`)

## Installation

### lazy.nvim

```lua
{
  "pedropombeiro/uncloak.nvim",
  ft = { "dotenv", "conf", "toml", "yaml" },
  opts = {},
}
```

## Configuration

All options with their defaults:

```lua
require("uncloak").setup({
  enabled = true,
  prefix = " 🔍 ",
  hl_group_prefix = "UncloakPrefix",  -- links to NonText
  hl_group_value  = "UncloakValue",   -- links to String
  hl_group_warn   = "UncloakWarn",    -- links to DiagnosticWarn
  max_len = 120,
  min_encoded_len = 8,
  min_printable_ratio = 0.75,
  debounce_ms = 150,

  -- Map filetypes to built-in parser names.
  filetypes = {
    dotenv = "env",
    conf   = "env",
    sh     = "env",
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
    eruby = "env",
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

Since the built-in `yaml` parser already handles `env:` blocks, you only need
to map the filetype. No custom parser required.

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
   candidate key-value pairs (with section scoping for TOML/YAML).
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
