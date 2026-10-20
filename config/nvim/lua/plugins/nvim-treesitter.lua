local parsers = {
    "lua",
    "python",
    "c",
    "rust",
    "markdown",
    "vim",
    "sql",
    "typescript",
    "tsx",
    "javascript",
    "html",
    "go",
}

local parser_by_filetype = {
    lua = "lua",
    python = "python",
    c = "c",
    rust = "rust",
    markdown = "markdown",
    vim = "vim",
    sql = "sql",
    typescript = "typescript",
    typescriptreact = "tsx",
    tsx = "tsx",
    javascript = "javascript",
    javascriptreact = "javascript",
    html = "html",
    go = "go",
}

local filetypes = {
    "lua",
    "python",
    "c",
    "rust",
    "markdown",
    "vim",
    "sql",
    "typescript",
    "typescriptreact",
    "tsx",
    "javascript",
    "javascriptreact",
    "html",
    "go",
}

local attached_parsers = {}

local function attach(buffer)
    local parser = parser_by_filetype[vim.bo[buffer].filetype]
    if not parser then
        return false
    end

    if attached_parsers[buffer] == parser then
        if parser ~= "rust" then
            vim.bo[buffer].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
        return true
    end
    if attached_parsers[buffer] then
        vim.treesitter.stop(buffer)
        attached_parsers[buffer] = nil
    end

    local available, tree = pcall(vim.treesitter.get_parser, buffer, parser)
    if not available or not tree then
        return false
    end

    local started = pcall(vim.treesitter.start, buffer, parser)
    if not started then
        return false
    end

    attached_parsers[buffer] = parser
    if parser ~= "rust" then
        vim.bo[buffer].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
    return true
end

return {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
        local treesitter = require("nvim-treesitter")

        treesitter.setup({
            install_dir = vim.fn.stdpath("data") .. "/site",
        })

        treesitter.install(parsers):await(vim.schedule_wrap(function(err, installed)
            if err or not installed then
                vim.notify("Some Treesitter parsers could not be installed.", vim.log.levels.WARN)
            end

            for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buffer) then
                    attach(buffer)
                end
            end
        end))

        local group = vim.api.nvim_create_augroup("NvimTreesitter", { clear = true })
        vim.api.nvim_create_autocmd("FileType", {
            group = group,
            pattern = filetypes,
            callback = function(event)
                attach(event.buf)
            end,
        })
        vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
            group = group,
            callback = function(event)
                attached_parsers[event.buf] = nil
            end,
        })
    end,
}
