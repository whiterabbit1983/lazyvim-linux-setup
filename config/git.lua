return {
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gedit", "Gread", "Gwrite", "Gclog" },
    keys = {
      { "<leader>gFs", "<cmd>Git<cr>", desc = "Git Status (Fugitive)" },
      { "<leader>gFc", "<cmd>Git commit<cr>", desc = "Git Commit (Fugitive)" },
      { "<leader>gFd", "<cmd>Gvdiffsplit<cr>", desc = "Git Diff vs Index (Fugitive)" },
      { "<leader>gFb", "<cmd>Git blame<cr>", desc = "Git Blame (Fugitive)" },
      { "<leader>gFl", "<cmd>Git log --oneline --decorate -50<cr>", desc = "Git Log (Fugitive)" },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signcolumn = true,
      numhl = false,
      linehl = false,
      current_line_blame = false,
      current_line_blame_opts = { delay = 400, virt_text_pos = "eol" },
    },
    keys = {
      { "<leader>gFt", "<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "Toggle Git Line Blame" },
    },
  },
  {
    "folke/which-key.nvim",
    optional = true,
    opts = { spec = { { "<leader>gF", group = "Fugitive" } } },
  },
}
