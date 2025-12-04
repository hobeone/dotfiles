return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    -- LazyVim config for treesitter.
    indent = { enable = true },
    highlight = { enable = true },
    folds = { enable = true },
    ensure_installed = {
      "go", -- Ensure the Go parser is installed
      "bash",
      "c",
      "diff",
      -- Add other languages as needed
    },
    -- You can set auto_install to true to automatically install missing parsers
    -- auto_install = true,
  },
  -- Build command to ensure parsers are updated
  build = ":TSUpdate",
}
