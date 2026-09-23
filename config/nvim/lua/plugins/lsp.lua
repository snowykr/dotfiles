local desired_servers = {
    "lua_ls",
    "ts_ls",
    "gopls",
    "rust_analyzer",
    "pyright",
    "clangd",
}

local function supports_current_platform(package_name)
    local has_platform, platform = pcall(require, "mason-core.platform")
    local has_registry, registry = pcall(require, "mason-registry")

    if not has_platform or not has_registry or not registry.has_package(package_name) then
        return true
    end

    local package = registry.get_package(package_name)
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

local function resolve_servers_for_current_platform(server_names)
    local has_mappings, mappings = pcall(require, "mason-lspconfig.mappings")

    if not has_mappings then
        local fallback_servers = {}
        for _, server_name in ipairs(server_names) do
            fallback_servers[server_name] = {}
        end
        return server_names, fallback_servers
    end

    local lspconfig_to_package = mappings.get_mason_map().lspconfig_to_package
    local ensure_installed = {}
    local servers = {}

    for _, server_name in ipairs(server_names) do
        local package_name = lspconfig_to_package[server_name]

        if not package_name or supports_current_platform(package_name) then
            ensure_installed[#ensure_installed + 1] = server_name
            servers[server_name] = {}
        end
    end

    return ensure_installed, servers
end

local ensure_installed, servers = resolve_servers_for_current_platform(desired_servers)

return {
    -- mason: LSP 서버 설치
    {
        "mason-org/mason.nvim",
        opts = {}
    },

    -- mason-lsconfig: mason 과 nvim-lspconfig 연결
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = { "mason-org/mason.nvim" },
        opts = {
            ensure_installed = ensure_installed,
            automatic_enable = false,
        },
    },

    -- nvim-lspconfig: LSP 설정
    {
        "neovim/nvim-lspconfig",
        opts = {
            servers = servers
        },
        config = function(_, opts)
            for server_name, server_config in pairs(opts.servers) do
                vim.lsp.config(server_name, server_config)
                vim.lsp.enable(server_name)
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
        end,
    }
}
