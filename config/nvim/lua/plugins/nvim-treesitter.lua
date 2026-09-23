return {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
        local configs = require("nvim-treesitter")

        configs.setup({
            ensure_installed = { "lua", "python", "c", "rust", "markdown", "vim", "sql", "typescript", "javascript", "html", "go" },
            sync_install = false,
            highlight = { enable = true },
            indent = {
                enable = true,
                disable = { "rust" },
            },
        })
    end
}
