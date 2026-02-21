-- Standalone loader for uncloak.nvim.
-- When using lazy.nvim with `opts`, lazy calls setup() itself and this file
-- is skipped thanks to the guard below.

if vim.g.loaded_uncloak then
  return
end
vim.g.loaded_uncloak = true

if vim.g.uncloak_auto_setup == false then
  return
end

require("uncloak").setup(vim.g.uncloak_options or {})
