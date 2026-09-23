local function is_ssh_session()
  return vim.env.SSH_CONNECTION ~= nil
    or vim.env.SSH_CLIENT ~= nil
    or vim.env.SSH_TTY ~= nil
end

return {
  "ojroques/nvim-osc52",
  cond = is_ssh_session,
  config = function()
    local function copy(lines, _)
      require("osc52").copy(table.concat(lines, "\n"))
    end

    local function paste()
      return {vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("")}
    end

    vim.g.clipboard = {
      name = "osc52",
      copy = {
        ["+"] = copy,
        ["*"] = copy,
      },
      paste = {
        ["+"] = paste,
        ["*"] = paste,
      },
    }
  end,
}
