return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = {
      "ToggleTerm",
      "TermExec",
    },
    config = function()
      require("toggleterm").setup({})
    end,
  },
}
