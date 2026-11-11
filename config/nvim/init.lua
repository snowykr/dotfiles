if vim.fn.has("nvim-0.12") == 0 then
    local version = vim.version()
    local message = ("dotfiles requires Neovim 0.12 or newer; running %d.%d.%d at %s. Upgrade Neovim before loading this configuration.")
        :format(version.major, version.minor, version.patch, vim.v.progpath)
    vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, {})
    if #vim.api.nvim_list_uis() == 0 then
        os.exit(1)
    end
    return
end

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.keymaps")
require("config.lazy")
require("config.local")
