-- Use second block as recommended approach.
-- if Interop is disabled in /etc/wsl.conf, this block will not work.
-- https://stackoverflow.com/a/76475346/5155214
if vim.fn.has("wsl") == 1 then
    vim.g.clipboard = {
        name = "WslClipboard",
        copy = {
            ["+"] = "clip.exe",
            ["*"] = "clip.exe",
        },
        paste = {
            ["+"] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
            ["*"] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
        },
        cache_enabled = 0,
    }
end
--
-- https://stackoverflow.com/questions/75548458/copy-into-system-clipboard-from-neovim
-- if vim.fn.has("wsl") == 1 then
--     if vim.fn.executable("wl-copy") == 0 then
--         print("wl-clipboard not found, clipboard integration won't work")
--     else
--         vim.g.clipboard = {
--             name = "wl-clipboard (wsl)",
--             copy = {
--                 ["+"] = "wl-copy --foreground --type text/plain",
--                 ["*"] = "wl-copy --foreground --primary --type text/plain",
--             },
--             paste = {
--                 ["+"] = function()
--                     return vim.fn.systemlist('wl-paste --no-newline|sed -e "s/\r$//"', { "" }, 1) -- '1' keeps empty lines
--                 end,
--                 ["*"] = function()
--                     return vim.fn.systemlist('wl-paste --primary --no-newline|sed -e "s/\r$//"', { "" }, 1)
--                 end,
--             },
--             cache_enabled = true,
--         }
--     end
-- end
