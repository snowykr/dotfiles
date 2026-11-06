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
local original_treesitter_stop = vim.treesitter.stop
local original_active_highlighters = vim.treesitter.highlighter.active
vim.treesitter.highlighter.active = {}
local stopped_buffers = {}
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
    vim.treesitter.highlighter.active[buffer] = { parser = parser }
end
vim.treesitter.stop = function(buffer)
    stopped_buffers[buffer] = (stopped_buffers[buffer] or 0) + 1
    started_buffers[buffer] = nil
    vim.treesitter.highlighter.active[buffer] = nil
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

-- FileType transitions must release only the highlighter this config owns.
vim.bo[python_buffer].filetype = "text"
equal(started_buffers[python_buffer], nil, "Unsupported FileType stops owned highlighting")
equal(stopped_buffers[python_buffer], 1, "Unsupported FileType stops exactly once")
equal(vim.bo[python_buffer].indentexpr, "keep-python-indent", "Detach restores native indentation")
vim.bo[python_buffer].filetype = "python"
equal(started_buffers[python_buffer], "python", "Supported FileType reattaches after unsupported type")
available_parsers.go = nil
vim.bo[python_buffer].filetype = "go"
equal(started_buffers[python_buffer], nil, "Missing mapped parser stops previous highlighting")
equal(vim.bo[python_buffer].indentexpr, "keep-python-indent", "Missing mapped parser restores native indentation")
vim.bo[python_buffer].filetype = "python"
equal(started_buffers[python_buffer], "python", "Supported type reattaches after missing mapped parser")
vim.bo[python_buffer].filetype = "c"
equal(started_buffers[python_buffer], nil, "Throwing mapped parser stops previous highlighting")

local external_buffer = open_filetype("text", "external-indent")
local external_highlighter = {}
vim.treesitter.highlighter.active[external_buffer] = external_highlighter
vim.bo[external_buffer].filetype = "lua"
equal(vim.treesitter.highlighter.active[external_buffer], external_highlighter, "Existing external highlighter is not replaced")
vim.bo[external_buffer].filetype = "text"
equal(stopped_buffers[external_buffer], nil, "Unsupported type does not stop an unowned highlighter")
local replacement = {}
vim.treesitter.highlighter.active[typescript_buffer] = replacement
vim.bo[typescript_buffer].indentexpr = "new-native-indent"
vim.bo[typescript_buffer].filetype = "text"
equal(vim.treesitter.highlighter.active[typescript_buffer], replacement, "Replacement highlighter is not stopped")
equal(stopped_buffers[typescript_buffer], nil, "Replaced ownership does not call stop")
equal(vim.bo[typescript_buffer].indentexpr, "new-native-indent", "Detach preserves newer native indentation")

-- Match Lazy startup order: native indentation precedes plugin autocommands.
vim.cmd("filetype indent on")
treesitter_plugin.config()
-- Native indentation can overwrite indentexpr when a same-parser filetype reloads.
local alias_highlighter = vim.treesitter.highlighter.active[javascript_buffer]
vim.bo[javascript_buffer].filetype = "javascriptreact"
equal(vim.treesitter.highlighter.active[javascript_buffer], alias_highlighter, "Same-parser alias retains owned highlighter")
equal(stopped_buffers[javascript_buffer], nil, "Same-parser alias never stops highlighting")
equal(vim.bo[javascript_buffer].indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()", "Same-parser FileType restores Treesitter indentation")
vim.bo[lua_buffer].indentexpr = "native-indent"
vim.bo[lua_buffer].filetype = "lua"
equal(vim.bo[lua_buffer].indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()", "Repeated Lua FileType restores Treesitter indentation")

-- Unloading detaches the real highlighter; reopening the same buffer must attach again.
vim.api.nvim_buf_delete(lua_buffer, { unload = true })
assert(vim.api.nvim_buf_is_valid(lua_buffer), "Unload retains buffer identity")
equal(started_buffers[lua_buffer], nil, "Unload stops owned highlighting")
vim.fn.bufload(lua_buffer)
vim.bo[lua_buffer].filetype = "lua"
equal(started_buffers[lua_buffer], "lua", "Reloading an unloaded buffer restarts highlighting")

vim.treesitter.get_parser = original_get_parser
vim.treesitter.start = original_treesitter_start
vim.treesitter.stop = original_treesitter_stop
vim.treesitter.highlighter.active = original_active_highlighters
vim.schedule_wrap = original_schedule_wrap
vim.api.nvim_del_augroup_by_name("NvimTreesitter")

-- Neovim ships a Lua parser: exercise actual highlighter state without fetching
-- any parser or plugin. The install stub is deliberately never completed here.
treesitter_plugin.config()
local native_buffer = open_filetype("lua", "")
local native_highlighter = vim.treesitter.highlighter.active[native_buffer]
assert(native_highlighter, "Bundled Lua parser creates a real highlighter")
vim.bo[native_buffer].filetype = "text"
equal(vim.treesitter.highlighter.active[native_buffer], nil, "Real highlighter detaches on unsupported FileType")
assert(vim.bo[native_buffer].indentexpr ~= "v:lua.require'nvim-treesitter'.indentexpr()", "Real detach restores native indentation")
vim.bo[native_buffer].filetype = "lua"
assert(vim.treesitter.highlighter.active[native_buffer], "Real highlighter reattaches on supported FileType")
vim.api.nvim_buf_delete(native_buffer, { unload = true })
equal(vim.treesitter.highlighter.active[native_buffer], nil, "Real unload removes highlighter")
vim.fn.bufload(native_buffer)
vim.bo[native_buffer].filetype = "lua"
assert(vim.treesitter.highlighter.active[native_buffer], "Real reload reattaches highlighter")
vim.api.nvim_buf_delete(native_buffer, { force = true })
vim.api.nvim_del_augroup_by_name("NvimTreesitter")

-- Dashboard uses the pinned Alpha button(sc, text, keybind) contract. Every
-- action has an explicit command, rather than feeding an unrelated global map.
local dashboard = { section = { buttons = { val = {} } }, config = {} }
dashboard.button = function(shortcut, text, command)
    assert(type(command) == "string", "Dashboard buttons require explicit commands")
    return { shortcut = shortcut, text = text, command = command }
end
package.preload["alpha.themes.dashboard"] = function()
    return dashboard
end
local alpha_config
package.preload["alpha"] = function()
    return { setup = function(config) alpha_config = config end }
end
dofile(repo .. "/config/nvim/lua/plugins/alpha.lua").config()
equal(alpha_config, dashboard.config, "Alpha receives dashboard layout")
local expected_buttons = {
    { "e", "New file", "<cmd>enew<CR>" },
    { "SPC f f", "Find files", "<cmd>Telescope find_files<CR>" },
    { "r", "Recently opened files", "<cmd>Telescope oldfiles<CR>" },
    { "SPC f g", "Search text", "<cmd>Telescope live_grep<CR>" },
    { "SPC f b", "Open buffers", "<cmd>Telescope buffers<CR>" },
    { "SPC f h", "Help tags", "<cmd>Telescope help_tags<CR>" },
}
equal(#dashboard.section.buttons.val, #expected_buttons, "Only implemented dashboard actions are shown")
local telescope_action
vim.api.nvim_create_user_command("Telescope", function(command)
    telescope_action = command.args
end, { nargs = 1 })
for index, expected in ipairs(expected_buttons) do
    local button = dashboard.section.buttons.val[index]
    equal(button.shortcut, expected[1], "Dashboard shortcut: " .. expected[2])
    equal(button.text, expected[2], "Dashboard action label")
    equal(button.command, expected[3], "Dashboard command matches label: " .. expected[2])
    local command = button.command:match("^<cmd>(.-)<CR>$")
    assert(command, "Dashboard action is an executable command")
    vim.cmd(command)
    if index == 1 then
        equal(vim.api.nvim_buf_get_name(0), "", "New file opens an unnamed buffer")
    else
        equal(telescope_action, expected[3]:match("Telescope ([%w_]+)"), "Dashboard dispatches labeled Telescope action")
    end
end
vim.api.nvim_del_user_command("Telescope")

local refresh_callback
local registry_ready = false
local refresh_count = 0
local function mason_package(installable)
    return {
        is_installable = function()
            assert(registry_ready, "Mason installability was checked before the registry callback")
            return installable
        end,
    }
end
local packages = {
    ["lua-language-server"] = mason_package(true),
    ["typescript-language-server"] = mason_package(true),
    gopls = mason_package(false),
    pyright = mason_package(false),
    clangd = mason_package(true),
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

-- Real clangd metadata restricts asset targets without supported_platforms.
-- Mason's installer compiler, not a guessed metadata field, decides availability.
packages.clangd = mason_package(false)
packages.clangd.spec = { source = { asset = { { target = "linux_x64_gnu" } } } }
registry_ready = false
configured_servers = {}
notifications = {}
mason_lsp_plugin.config()
registry_ready = true
refresh_callback(true, {})
equal_array(installed_server_options.ensure_installed, { "lua_ls", "ts_ls" }, "Unsupported asset target is not installed")
equal_array(installed_server_options.automatic_enable, { "lua_ls", "ts_ls" }, "Unsupported asset target is not activated")
equal(configured_servers.clangd, nil, "Non-installable clangd is not configured")
assert(notifications[1].message:find("clangd", 1, true), "Unavailable asset is reported")

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

-- Clone failures must exit headless jobs, while an attached UI may acknowledge
-- the diagnostic before exiting. No network requests or process exits occur here.
local function check_bootstrap_failure(uis, expected_reads)
    local saved_stat = vim.uv.fs_stat
    local saved_system = vim.fn.system
    local saved_echo = vim.api.nvim_echo
    local saved_uis = vim.api.nvim_list_uis
    local saved_getchar = vim.fn.getchar
    local saved_exit = os.exit
    local reads = 0
    local exit_code
    local echoed
    local stopped = {}

    vim.uv.fs_stat = function()
        return nil
    end
    vim.fn.system = function(command)
        equal_array(command, {
            "git", "clone", "--filter=blob:none", "--branch=stable",
            "https://github.com/folke/lazy.nvim.git",
            vim.fn.stdpath("data") .. "/lazy/lazy.nvim",
        }, "Bootstrap clone command")
        saved_system({ "sh", "-c", "exit 1" })
        return "deliberate clone failure"
    end
    vim.api.nvim_echo = function(chunks)
        echoed = ""
        for _, chunk in ipairs(chunks) do
            echoed = echoed .. chunk[1]
        end
    end
    vim.api.nvim_list_uis = function()
        return uis
    end
    vim.fn.getchar = function()
        reads = reads + 1
        return 0
    end
    os.exit = function(code)
        exit_code = code
        error(stopped, 0)
    end

    local ok, err = pcall(dofile, repo .. "/config/nvim/lua/config/lazy.lua")
    vim.uv.fs_stat = saved_stat
    vim.fn.system = saved_system
    vim.api.nvim_echo = saved_echo
    vim.api.nvim_list_uis = saved_uis
    vim.fn.getchar = saved_getchar
    os.exit = saved_exit

    equal(ok, false, "Failed bootstrap exits instead of loading plugins")
    equal(err, stopped, "Failed bootstrap reaches the deliberate exit")
    equal(exit_code, 1, "Failed bootstrap reports a failing exit status")
    equal(reads, expected_reads, "Only an attached UI waits for acknowledgement")
    assert(echoed:find("deliberate clone failure", 1, true), "Bootstrap retains clone diagnostics")
    equal(echoed:find("Press any key", 1, true) ~= nil, expected_reads > 0, "Only an attached UI prompts")
end

check_bootstrap_failure({}, 0)
check_bootstrap_failure({ { chan = 1 } }, 1)
print("Offline Neovim configuration tests passed.")
