-- Machine-local overrides live outside this checkout so updates never touch them.
-- Loaded last, after plugins, so anything set here wins. Errors are not hidden:
-- a broken override file fails loudly at startup instead of being ignored.
local override_path = vim.fn.expand("~/.config/dotfiles/local/nvim.lua")

if vim.fn.filereadable(override_path) == 1 then
    dofile(override_path)
end
