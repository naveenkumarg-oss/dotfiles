return {
    "neo-tree.nvim",
    dependencies = {
      "nvim-tree/nvim-web-devicons"
    },
    opts = {
      filesystem = {
        filtered_items = {
          --visible = true,
          hide_dotfiles = false,
          hide_gitignored = true,
          hide_by_name = {
            ".github",
            ".gitignore",
            "package-lock.json",
          },
          never_show = { ".git" },
        },
      },
    },
  }