local desired_servers = {
    "lua_ls",
    "ts_ls",
    "gopls",
    "rust_analyzer",
    "pyright",
    "clangd",
}

local function supports_current_platform(package, platform)
    local supported_platforms = vim.tbl_get(package, "spec", "source", "supported_platforms")
    if type(supported_platforms) ~= "table" or vim.tbl_isempty(supported_platforms) then
        return true
    end

    for _, supported_platform in ipairs(supported_platforms) do
        if platform.is[supported_platform] then
            return true
        end
    end

    return false
end

local function resolve_servers_for_current_platform(registry)
    local lspconfig_to_package = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
    local platform = require("mason-core.platform")
    local ensure_installed = {}
    local servers = {}
    local unavailable = {}

    for _, server_name in ipairs(desired_servers) do
        local package_name = lspconfig_to_package[server_name]
        local package
        if package_name and registry.has_package(package_name) then
            package = registry.get_package(package_name)
        end

        if package and supports_current_platform(package, platform) then
            ensure_installed[#ensure_installed + 1] = server_name
            servers[server_name] = {}
        else
            unavailable[#unavailable + 1] = server_name
        end
    end

    if #unavailable > 0 then
        vim.notify(
            "Skipping LSP servers without an available Mason package for this platform: "
                .. table.concat(unavailable, ", "),
            vim.log.levels.WARN
        )
    end

    return ensure_installed, servers
end

local function configure_lsp(servers)
    for server_name, server_config in pairs(servers) do
        vim.lsp.config(server_name, server_config)
    end

    local group = vim.api.nvim_create_augroup("LspKeymaps", { clear = true })
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(event)
            local map_opts = { buffer = event.buf, silent = true }
            vim.keymap.set("n", "K", vim.lsp.buf.hover, map_opts)
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, map_opts)
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, map_opts)
        end,
    })
end

return {
    {
        "mason-org/mason.nvim",
        opts = {},
    },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
        config = function()
            local registry = require("mason-registry")
            registry.refresh(function(success)
                if not success then
                    vim.notify(
                        "Mason registry refresh failed; checking available cached packages.",
                        vim.log.levels.WARN
                    )
                end

                local ensure_installed, servers = resolve_servers_for_current_platform(registry)
                configure_lsp(servers)
                require("mason-lspconfig").setup({
                    ensure_installed = ensure_installed,
                    automatic_enable = ensure_installed,
                })
            end)
        end,
    },
    {
        "neovim/nvim-lspconfig",
    },
}
