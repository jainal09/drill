-- ============================================================================
-- explorer.lua -- the optional file-explorer sidebar behind Ctrl+B / Cmd+B.
--
-- drill's one deliberate exception to "no plugins": nvim-tree draws the tree,
-- volt+menu will draw the right-click menu, all vendored at pinned SHAs by
-- vendor.sh. Nothing in this file runs -- the checkouts are not even on
-- 'runtimepath' -- until the first toggle, so an editor that never presses
-- Ctrl+B is byte-for-byte the editor drill has always been.
--
-- Loaded with dofile() from nvimrc.lua, not require(): drill's own code is
-- found by path, never by 'runtimepath', same as preload.py.
-- ============================================================================

local M = {}

local HERE = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local VENDOR = HERE .. "/vendor"

-- The checks live here, not in the toggle: dofile() runs once, and a missing
-- checkout or an old nvim is a property of the install, not of the keypress.
-- M.error is the single source of truth; the toggle just repeats it.
if vim.fn.has("nvim-0.10") == 0 then
  M.error = "drill: the sidebar needs nvim 0.10+ -- everything else still works"
end
for _, d in ipairs({ "nvim-tree.lua", "volt", "menu" }) do
  if not M.error and vim.fn.isdirectory(VENDOR .. "/" .. d .. "/lua") == 0 then
    M.error = "drill: sidebar plugins are not fetched -- run " .. HERE .. "/vendor.sh"
  end
end

local host = { type_here = function() end }
local ready = false

function M.setup(h)
  if M.error or ready then return end
  host = h
  for _, d in ipairs({ "nvim-tree.lua", "volt", "menu" }) do
    vim.opt.runtimepath:prepend(VENDOR .. "/" .. d)
  end
  require("nvim-tree").setup({
    disable_netrw = false,          -- bare `d` keeps its netrw listing
    hijack_netrw = false,
    git = { enable = false },       -- solves/ is scratch; no gutter ceremony
    diagnostics = { enable = false },
    update_focused_file = { enable = true },
    view = { width = 32, preserve_window_proportions = true },
    renderer = {
      special_files = {},
      icons = {
        show = { file = false, folder = false, folder_arrow = true,
                 git = false, modified = false, bookmarks = true },
        -- ASCII on purpose: drill promises zero setup, and nerd-font glyphs
        -- are tofu boxes on a stock terminal font.
        glyphs = { folder = { arrow_closed = "+", arrow_open = "-" },
                   bookmark = "*" },
      },
    },
    actions = {
      open_file = {
        window_picker = {
          -- the default exclude already refuses terminal/nofile/help, so a
          -- file opened from the tree can never land in the interpreter;
          -- netrw is drill's own listing and must not eat an open either
          exclude = {
            buftype = { "nofile", "terminal", "help" },
            filetype = { "netrw", "notify", "qf", "diff" },
          },
        },
      },
    },
    on_attach = function(bufnr) M.attach(bufnr) end,
  })
  ready = true
end

-- Buffer-local extras on top of nvim-tree's stock keymap. Buffer-local is
-- load-bearing: suite_options asserts the GLOBAL mouse maps stay exactly as
-- the mouse section left them, and nothing here may show up there.
function M.attach(bufnr)
  require("nvim-tree.api").config.mappings.default_on_attach(bufnr)
end

function M.toggle()
  if M.error then
    vim.notify(M.error, vim.log.levels.WARN)
    return
  end
  -- focus=false: the sidebar appears, the caret stays in your code -- the
  -- mouse is how you enter the tree. type_here() on both directions, so the
  -- toggle keeps drill's one promise: wherever you land, you are typing.
  require("nvim-tree.api").tree.toggle({ focus = false })
  host.type_here()
end

return M
