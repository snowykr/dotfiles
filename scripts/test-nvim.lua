local script_path = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(script_path, ":p:h:h")
package.path = repo .. "/config/nvim/lua/?.lua;" .. repo .. "/config/nvim/lua/?/init.lua;" .. package.path

local function equal(actual, expected, label)
    assert(actual == expected, ("%s: expected %s, got %s"):format(label, vim.inspect(expected), vim.inspect(actual)))
end

local function equal_array(actual, expected, label)
    equal(#actual, #expected, label .. " length")
    for index, value in ipairs(expected) do
        equal(actual[index], value, label .. "[" .. index .. "]")
    end
end

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

local treesitter_setup
local installed_parsers
local complete_install
package.preload["nvim-treesitter"] = function()
    return {
        setup = function(opts)
            treesitter_setup = opts
        end,
        install = function(requested)
            installed_parsers = requested
            return {
                await = function(_, callback)
                    complete_install = callback
                end,
            }
        end,
    }
end

local available_parsers = { rust = true, javascript = true, typescript = true, tsx = true }
local requested_parsers = {}
local started_buffers = {}
local original_get_parser = vim.treesitter.get_parser
local original_treesitter_start = vim.treesitter.start
local original_schedule_wrap = vim.schedule_wrap
vim.treesitter.get_parser = function(buffer, parser)
    requested_parsers[#requested_parsers + 1] = { buffer = buffer, parser = parser }
    if parser == "c" then
        error("Parser is not installed: " .. parser)
    end
    if not available_parsers[parser] then
        return nil, "Parser is not installed: " .. parser
    end
    return { lang = parser }
end
vim.treesitter.start = function(buffer, parser)
    started_buffers[buffer] = parser
end
vim.schedule_wrap = function(callback)
    return callback
end

local treesitter_plugin = dofile(repo .. "/config/nvim/lua/plugins/nvim-treesitter.lua")
treesitter_plugin.config()
equal_array(installed_parsers, parsers, "Treesitter parser install list")
equal(treesitter_setup.install_dir, vim.fn.stdpath("data") .. "/site", "Treesitter install directory")

local function open_filetype(filetype, indentexpr)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].indentexpr = indentexpr
    vim.bo[buffer].filetype = filetype
    return buffer
end

local lua_buffer = open_filetype("lua", "keep-lua-indent")
equal(started_buffers[lua_buffer], nil, "Treesitter skips Lua before parser installation")
equal(vim.bo[lua_buffer].indentexpr, "keep-lua-indent", "Missing parser leaves Lua indentation unchanged")

local rust_buffer = open_filetype("rust", "keep-rust-indent")
equal(started_buffers[rust_buffer], "rust", "Treesitter starts highlighting for Rust")
equal(vim.bo[rust_buffer].indentexpr, "keep-rust-indent", "Treesitter leaves Rust indentation unchanged")

local javascript_buffer = open_filetype("javascript", "")
equal(started_buffers[javascript_buffer], "javascript", "JavaScript uses JavaScript parser")
local typescript_buffer = open_filetype("typescript", "")
equal(started_buffers[typescript_buffer], "typescript", "TypeScript uses TypeScript parser")
local javascript_react_buffer = open_filetype("javascriptreact", "")
equal(started_buffers[javascript_react_buffer], "javascript", "JavaScript React uses JavaScript parser")
local typescript_react_buffer = open_filetype("typescriptreact", "")
equal(started_buffers[typescript_react_buffer], "tsx", "TypeScript React uses TSX parser")
local function requested_parser(buffer)
    for _, request in ipairs(requested_parsers) do
        if request.buffer == buffer then
            return request.parser
        end
    end
end
equal(requested_parser(javascript_react_buffer), "javascript", "JavaScript React parser mapping")
equal(requested_parser(typescript_react_buffer), "tsx", "TypeScript React parser mapping")
local tsx_buffer = open_filetype("tsx", "")
equal(started_buffers[tsx_buffer], "tsx", "TSX filetype uses TSX parser")

local c_buffer = open_filetype("c", "keep-c-indent")
equal(started_buffers[c_buffer], nil, "A parser lookup error does not escape the FileType callback")
equal(vim.bo[c_buffer].indentexpr, "keep-c-indent", "A parser lookup error leaves indentation unchanged")

local text_buffer = open_filetype("text", "keep-unsupported-indent")
equal(started_buffers[text_buffer], nil, "Treesitter ignores unsupported filetypes")
equal(vim.bo[text_buffer].indentexpr, "keep-unsupported-indent", "Treesitter leaves unsupported indentation unchanged")

local python_buffer = open_filetype("python", "keep-python-indent")
equal(started_buffers[python_buffer], nil, "Missing parser does not throw while opening a Python buffer")
equal(vim.bo[python_buffer].indentexpr, "keep-python-indent", "Missing Python parser leaves indentation unchanged")

for _, parser in ipairs(parsers) do
    available_parsers[parser] = true
end
complete_install(nil, true)
equal(started_buffers[lua_buffer], "lua", "Install completion attaches existing Lua buffer")
equal(vim.bo[lua_buffer].indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()", "Lua indentation is enabled after parser install")
equal(started_buffers[python_buffer], "python", "Install completion attaches existing Python buffer")
equal(vim.bo[python_buffer].indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()", "Python indentation is enabled after parser install")
equal(started_buffers[typescript_react_buffer], "tsx", "Install completion retains TSX mapping")
equal(started_buffers[tsx_buffer], "tsx", "Install completion retains TSX filetype mapping")
equal(vim.bo[rust_buffer].indentexpr, "keep-rust-indent", "Install completion continues to skip Rust indentation")

-- Match Lazy startup order: native indentation precedes plugin autocommands.
vim.cmd("filetype indent on")
treesitter_plugin.config()
-- Native indentation can overwrite indentexpr when a same-parser filetype reloads.
vim.bo[javascript_buffer].filetype = "javascriptreact"
equal(vim.bo[javascript_buffer].indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()", "Same-parser FileType restores Treesitter indentation")
vim.bo[lua_buffer].indentexpr = "native-indent"
vim.bo[lua_buffer].filetype = "lua"
equal(vim.bo[lua_buffer].indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()", "Repeated Lua FileType restores Treesitter indentation")

-- Unloading detaches the real highlighter; reopening the same buffer must attach again.
vim.api.nvim_buf_delete(lua_buffer, { unload = true })
assert(vim.api.nvim_buf_is_valid(lua_buffer), "Unload retains buffer identity")
started_buffers[lua_buffer] = nil
vim.fn.bufload(lua_buffer)
vim.bo[lua_buffer].filetype = "lua"
equal(started_buffers[lua_buffer], "lua", "Reloading an unloaded buffer restarts highlighting")

vim.treesitter.get_parser = original_get_parser
vim.treesitter.start = original_treesitter_start
vim.schedule_wrap = original_schedule_wrap

local refresh_callback
local registry_ready = false
local refresh_count = 0
local packages = {
    ["lua-language-server"] = { spec = { source = { supported_platforms = { "darwin_arm64" } } } },
    ["typescript-language-server"] = { spec = { source = {} } },
    gopls = { spec = { source = { supported_platforms = { "linux_x64" } } } },
    pyright = { spec = { source = { supported_platforms = { "linux_x64" } } } },
    clangd = { spec = { source = { supported_platforms = {} } } },
}
local registry = {
    refresh = function(callback)
        refresh_count = refresh_count + 1
        refresh_callback = callback
    end,
    has_package = function(name)
        assert(registry_ready, "Mason package availability was checked before the registry callback")
        return packages[name] ~= nil
    end,
    get_package = function(name)
        assert(registry_ready, "Mason package lookup happened before the registry callback")
        assert(packages[name], "Unexpected Mason package lookup: " .. name)
        return packages[name]
    end,
}
package.preload["mason-registry"] = function()
    return registry
end

local platform = {
    is = setmetatable({ darwin_arm64 = true }, {
        __index = function()
            return false
        end,
    }),
}
package.preload["mason-core.platform"] = function()
    assert(registry_ready, "Mason platform filtering happened before the registry callback")
    return platform
end

local mapping_reads = 0
package.preload["mason-lspconfig.mappings"] = function()
    assert(registry_ready, "Mason mappings were read before the registry callback")
    return {
        get_mason_map = function()
            mapping_reads = mapping_reads + 1
            return {
                lspconfig_to_package = {
                    lua_ls = "lua-language-server",
                    ts_ls = "typescript-language-server",
                    gopls = "gopls",
                    rust_analyzer = "rust-analyzer",
                    pyright = "pyright",
                    clangd = "clangd",
                },
            }
        end,
    }
end

local installed_server_options
local mason_setup_count = 0
package.preload["mason-lspconfig"] = function()
    return {
        setup = function(opts)
            assert(registry_ready, "Mason LSP setup happened before the registry callback")
            mason_setup_count = mason_setup_count + 1
            installed_server_options = opts
        end,
    }
end

local configured_servers = {}
local enabled_servers = {}
local original_lsp_config = vim.lsp.config
local original_lsp_enable = vim.lsp.enable
vim.lsp.config = function(name, opts)
    configured_servers[name] = opts
end
vim.lsp.enable = function(name)
    enabled_servers[name] = true
end

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
end

local lsp_plugins = dofile(repo .. "/config/nvim/lua/plugins/lsp.lua")
local mason_lsp_plugin = lsp_plugins[2]
mason_lsp_plugin.config()
equal(refresh_count, 1, "LSP config refreshes the registry")
equal(mapping_reads, 0, "LSP mappings are not read before registry refresh callback")
equal(mason_setup_count, 0, "Mason LSP setup waits for registry refresh callback")
equal(next(configured_servers), nil, "LSP servers are not configured before registry refresh callback")
equal(next(enabled_servers), nil, "LSP servers are not enabled before registry refresh callback")

registry_ready = true
refresh_callback(true, {})
equal(mason_setup_count, 1, "Mason LSP is set up after registry refresh")
equal(mapping_reads, 1, "Mason mappings are read after registry refresh")
equal_array(installed_server_options.ensure_installed, { "lua_ls", "ts_ls", "clangd" }, "Platform-filtered install list")
equal_array(installed_server_options.automatic_enable, { "lua_ls", "ts_ls", "clangd" }, "Automatic activation uses the platform-filtered list")
equal(next(enabled_servers), nil, "Server activation is delegated to Mason installation lifecycle")
for _, server in ipairs({ "lua_ls", "ts_ls", "clangd" }) do
    assert(configured_servers[server], "Expected server to be configured: " .. server)
    assert(vim.list_contains(installed_server_options.automatic_enable, server), "Expected server selected for automatic activation: " .. server)
end
for _, server in ipairs({ "gopls", "rust_analyzer", "pyright" }) do
    equal(configured_servers[server], nil, "Unsupported or missing package is not configured: " .. server)
    assert(not vim.list_contains(installed_server_options.automatic_enable, server), "Unsupported or missing package is not automatically enabled: " .. server)
end
for server in pairs(configured_servers) do
    assert(vim.list_contains(installed_server_options.automatic_enable, server), "Configured server is absent from automatic activation list: " .. server)
end
for _, server in ipairs(installed_server_options.automatic_enable) do
    assert(configured_servers[server], "Automatic activation selected an unconfigured server: " .. server)
end
assert(#notifications > 0, "Unavailable and unsupported packages are reported")

registry_ready = false
refresh_callback = nil
configured_servers = {}
enabled_servers = {}
installed_server_options = nil
mason_lsp_plugin.config()
equal(refresh_count, 2, "LSP config refreshes the registry on each setup")
-- A failed network refresh does not invalidate usable cached package metadata.
registry_ready = true
refresh_callback(false, {})
equal(mason_setup_count, 2, "Failed registry refresh still configures cached packages")
equal_array(installed_server_options.ensure_installed, { "lua_ls", "ts_ls", "clangd" }, "Cached platform-filtered install list")
for _, server in ipairs({ "lua_ls", "ts_ls", "clangd" }) do
    assert(configured_servers[server], "Cached server is configured while offline: " .. server)
    assert(vim.list_contains(installed_server_options.automatic_enable, server), "Cached server is selected for offline activation: " .. server)
end
for _, server in ipairs({ "gopls", "rust_analyzer", "pyright" }) do
    assert(not vim.list_contains(installed_server_options.automatic_enable, server), "Offline activation excludes unsupported or missing package: " .. server)
end

-- A cold, failed refresh has no usable packages and must not fail open.
registry_ready = false
packages = {}
configured_servers = {}
enabled_servers = {}
mason_lsp_plugin.config()
registry_ready = true
refresh_callback(false, {})
equal_array(installed_server_options.ensure_installed, {}, "Failed cold refresh installs no unknown packages")
equal(next(configured_servers), nil, "Failed cold refresh configures no unknown servers")
equal(next(enabled_servers), nil, "Failed cold refresh enables no unknown servers")
local refresh_failure_reported = false
for _, notification in ipairs(notifications) do
    if notification.message:find("Mason registry refresh failed", 1, true) then
        refresh_failure_reported = true
        equal(notification.level, vim.log.levels.WARN, "Refresh failure is reported as a warning")
    end
end
assert(refresh_failure_reported, "Failed registry refresh reports a warning")

vim.lsp.config = original_lsp_config
vim.lsp.enable = original_lsp_enable
vim.notify = original_notify
print("Offline Neovim configuration tests passed.")
