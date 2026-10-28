-- Machine-local overrides live outside this checkout so updates never touch them.
-- Runs last in init.lua, after options, keymaps and the lazy.nvim plugin manager,
-- so plugins that load lazily afterwards can still change options. Errors are not
-- hidden: a broken override file surfaces at startup instead of being ignored.
local override_path = vim.fn.expand("~/.config/dotfiles/local/nvim.lua")

if vim.fn.filereadable(override_path) == 1 then
    dofile(override_path)
end
