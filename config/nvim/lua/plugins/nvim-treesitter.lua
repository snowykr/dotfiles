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

local attached_parsers = {}
local indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

local function detach(buffer)
    local attached = attached_parsers[buffer]
    if not attached then
        return
    end
    if vim.treesitter.highlighter.active[buffer] == attached.highlighter then
        vim.treesitter.stop(buffer)
    end
    if vim.bo[buffer].indentexpr == indentexpr then
        vim.bo[buffer].indentexpr = attached.indentexpr
    end
    attached_parsers[buffer] = nil
end

local function attach(buffer)
    local parser = parser_by_filetype[vim.bo[buffer].filetype]
    local attached = attached_parsers[buffer]
    local highlighter = vim.treesitter.highlighter.active[buffer]
    if attached and attached.parser == parser and attached.highlighter == highlighter then
        if parser ~= "rust" then
            if vim.bo[buffer].indentexpr ~= indentexpr then
                attached.indentexpr = vim.bo[buffer].indentexpr
            end
            vim.bo[buffer].indentexpr = indentexpr
        end
        return true
    end
    detach(buffer)
    if not parser or vim.treesitter.highlighter.active[buffer] then
        return false
    end

    local available, tree = pcall(vim.treesitter.get_parser, buffer, parser)
    if not available or not tree then
        return false
    end

    local started = pcall(vim.treesitter.start, buffer, parser)
    if not started then
        return false
    end

    highlighter = vim.treesitter.highlighter.active[buffer]
    if not highlighter then
        return false
    end
    attached_parsers[buffer] = {
        parser = parser,
        highlighter = highlighter,
        indentexpr = vim.bo[buffer].indentexpr,
    }
    if parser ~= "rust" then
        vim.bo[buffer].indentexpr = indentexpr
    end
    return true
end

return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    version = false,
    lazy = false,
    build = ":TSUpdate",
    config = function()
        local treesitter = require("nvim-treesitter")
        if type(treesitter.install) ~= "function" then
            error("Incompatible nvim-treesitter: the main-branch install API is missing. "
                .. "Back up local lazy-lock.json changes, then run :Lazy update nvim-treesitter "
                .. "with Neovim 0.12 or newer and restart Neovim.", 0)
        end

        treesitter.setup({
            install_dir = vim.fn.stdpath("data") .. "/site",
        })

        treesitter.install(parsers):await(vim.schedule_wrap(function(err, installed)
            if err or not installed then
                vim.notify("Some Treesitter parsers could not be installed.", vim.log.levels.WARN)
            end

            -- setup may register a site directory before it exists. Reassigning
            -- the option invalidates Neovim's cached runtime directory list.
            vim.o.runtimepath = vim.o.runtimepath
            for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buffer) then
                    attach(buffer)
                end
            end
        end))

        local group = vim.api.nvim_create_augroup("NvimTreesitter", { clear = true })
        vim.api.nvim_create_autocmd("FileType", {
            group = group,
            pattern = "*",
            callback = function(event)
                attach(event.buf)
            end,
        })
        vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
            group = group,
            callback = function(event)
                detach(event.buf)
            end,
        })
    end,
}
