-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  -- import/override with your plugins folder
  { import = "astrocommunity.editing-support.rainbow-delimiters-nvim" },
  { import = "astrocommunity.editing-support.comment-box-nvim" },
  { import = "astrocommunity.indent.indent-rainbowline" },
  -- :Codeium Auth | <C-g>: accept suggestion
  { import = "astrocommunity.completion.codeium-vim" },
}