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
local tree_menu   -- defined below the toolbar; setup's right-click map closes over it

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

  -- drill lives in insert mode, and a mouse press from insert FOCUSES the
  -- tree while STAYING in insert -- measured: mode "i", filetype NvimTree --
  -- so the release arrived in a mode none of the tree's mappings own and
  -- every click ate itself. There is nothing to type in a tree: entering it,
  -- by any route, lands you in Normal, and every gesture below can assume it.
  vim.api.nvim_create_autocmd("WinEnter", {
    group = vim.api.nvim_create_augroup("DrillTree", { clear = true }),
    callback = function()
      if vim.bo.filetype == "NvimTree" then vim.cmd("stopinsert") end
    end,
  })

  -- Right-click, global but late: this mapping exists only once the sidebar
  -- has been toggled at all, and everywhere outside the tree it re-feeds the
  -- unmapped key, so the file buffer keeps whatever stock right-click this
  -- nvim came with ('mousemodel' popup_setpos and its built-in menu today).
  -- Global is forced by how mouse events route: a right-click ON the tree
  -- while you are typing in the file is delivered to the FILE buffer's maps,
  -- so a tree-buffer-local mapping would simply never fire.
  vim.keymap.set({ "n", "i" }, "<RightMouse>", function()
    local mp = vim.fn.getmousepos()
    local b = mp.winid ~= 0 and vim.api.nvim_win_get_buf(mp.winid)
    if b and vim.bo[b].filetype == "NvimTree" then
      tree_menu()
    else
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<RightMouse>", true, true, true), "n", false)
    end
  end, { silent = true })

  -- Ctrl-click multi-select, same shape as right-click and global for the
  -- same routing reason. Outside the tree it re-feeds a PLAIN press, which
  -- is exactly what the mouse section's Ctrl-stripping maps did before this
  -- override -- nvim's stock <C-LeftMouse> is a tag jump that wedges a
  -- tagless editor behind a modal E426. On a tree row it toggles the mark
  -- (rendered as *), and a later drag of any marked row moves the whole set.
  vim.keymap.set({ "n", "i" }, "<C-LeftMouse>", function()
    local mp = vim.fn.getmousepos()
    local b = mp.winid ~= 0 and vim.api.nvim_win_get_buf(mp.winid)
    if b and vim.bo[b].filetype == "NvimTree" and mp.line > 0 then
      vim.api.nvim_set_current_win(mp.winid)
      pcall(vim.api.nvim_win_set_cursor, mp.winid, { mp.line, 0 })
      require("nvim-tree.api").marks.toggle()
    else
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true), "n", false)
    end
  end, { silent = true })
  ready = true
end

-- ----------------------------------------------------------------------------
-- The toolbar: real clickable [+ File] / [+ Folder] buttons, because "press a"
-- is not a button. The winbar takes %@handler@label%X click regions (core
-- since 0.8), and the handlers must be globals for v:lua to reach them --
-- namespaced DrillTree* so they collide with nothing.
--
-- Both prompt for the name with vim.ui.input, seeded with the directory the
-- tree cursor is on (a folder row means "in here", a file row means "next to
-- me") -- click a folder, click the button, type a name. The folder button
-- does NOT ride api.fs.create's trailing-slash convention: that is the same
-- keyboard folklore the button exists to retire. mkdir -p, reload, done.

local function cursor_dir()
  local api = require("nvim-tree.api")
  local node = api.tree.get_node_under_cursor()
  if node and node.nodes then return node.absolute_path end        -- a folder
  if node and node.parent then return node.parent.absolute_path end
  return vim.fn.getcwd()
end

function _G.DrillTreeNewFile()
  require("nvim-tree.api").fs.create()
end

function _G.DrillTreeNewFolder()
  local base = cursor_dir()
  vim.ui.input({ prompt = "New folder: ", default = base .. "/" }, function(path)
    if not path or path == "" or path:sub(-1) == "/" then return end
    vim.fn.mkdir(path, "p")
    require("nvim-tree.api").tree.reload()
  end)
end

local TOOLBAR = table.concat({
  " %@v:lua.DrillTreeNewFile@[+ File]%X",
  "%@v:lua.DrillTreeNewFolder@[+ Folder]%X",
}, "  ")

-- ----------------------------------------------------------------------------
-- The right-click menu. menu/volt do the drawing and the item clicks; the
-- items are drill's own -- plain ASCII labels, not the upstream set, whose
-- names are nerd-font glyphs (tofu on a stock terminal font) and whose "New
-- folder" entry is the trailing-slash convention wearing a menu costume.
-- Every cmd acts on the node under the tree cursor, which the right-click
-- parked there first.

local function menu_items()
  local api = require("nvim-tree.api")
  return {
    { name = "New file",       cmd = function() api.fs.create() end,        rtxt = "a" },
    { name = "New folder",     cmd = _G.DrillTreeNewFolder,                 rtxt = "A" },
    { name = "separator" },
    { name = "Open",           cmd = function() api.node.open.edit() end,   rtxt = "<CR>" },
    { name = "Open in split",  cmd = function() api.node.open.vertical() end, rtxt = "v" },
    { name = "separator" },
    { name = "Rename",         cmd = function() api.fs.rename() end,        rtxt = "r" },
    { name = "Cut",            cmd = function() api.fs.cut() end,           rtxt = "x" },
    { name = "Copy",           cmd = function() api.fs.copy.node() end,     rtxt = "c" },
    { name = "Paste",          cmd = function() api.fs.paste() end,         rtxt = "p" },
    { name = "separator" },
    { name = "Delete",         cmd = function() api.fs.remove() end,        rtxt = "d" },
  }
end

function tree_menu()
  local mp = vim.fn.getmousepos()
  if mp.winid == 0 then return end
  -- Focus the tree and park its cursor on the clicked row FIRST: the item
  -- cmds all mean "the node under the cursor", and the menu float itself
  -- opens unfocused, so this is what "right-clicked that file" resolves to.
  vim.api.nvim_set_current_win(mp.winid)
  if mp.line > 0 then
    pcall(vim.api.nvim_win_set_cursor, mp.winid, { mp.line, 0 })
  end
  require("menu.utils").delete_old_menus()
  -- menu leaves its auto-close <LeftMouse> map behind when a menu is closed
  -- by an item click rather than an outside click; clear the stale one so
  -- it cannot stack
  pcall(vim.keymap.del, "n", "<LeftMouse>")
  require("menu").open(menu_items(), { mouse = true, border = true })
end

-- ----------------------------------------------------------------------------
-- Drag a file onto a folder to move it. No plugin ships this; the events do:
-- the press parks the cursor on the source row (built-in), the first
-- <LeftDrag> report snapshots that node, and the release resolves the row
-- under the mouse into the destination. Dropping on a folder moves INTO it,
-- on a file moves NEXT TO it (paste targets the node's directory), and a
-- release back on the source row is not a drag at all -- that is a trackpad
-- click that jittered, the exact gesture mouse_drive.py's jitter cases exist
-- for, and it falls through to the ordinary click below.
--
-- If the dragged node is one of the marked ones (ctrl-click, below), the
-- whole marked set rides along: cut accumulates, one paste moves them all.

local drag_src = nil

local function node_at(row)
  local api = require("nvim-tree.api")
  local win = vim.fn.bufwinid(vim.api.nvim_get_current_buf())
  pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
  return api.tree.get_node_under_cursor()
end

local function drop(src, target)
  local api = require("nvim-tree.api")
  local moving = { src }
  local marks = api.marks.list()
  for _, n in ipairs(marks) do
    if n.absolute_path == src.absolute_path then
      moving = marks                       -- dragged one of the marked: all go
      break
    end
  end
  for _, n in ipairs(moving) do api.fs.cut(n) end
  api.fs.paste(target)
  api.fs.clear_clipboard()
  if moving == marks then api.marks.clear() end
  api.tree.reload()
end

-- A left-click, decomposed. The press already moved the cursor to the row
-- (built-in), so the release only has to act on the node under it. Guard on
-- getmousepos().line == 0: that is the winbar, whose clicks belong to the
-- %@ handlers above, not to the tree.
local function tree_drag()
  if drag_src == nil then
    -- first motion report of this gesture: the press has already parked the
    -- cursor on the source row, so this IS the source
    drag_src = require("nvim-tree.api").tree.get_node_under_cursor() or false
  end
end

local function tree_click()
  local mp = vim.fn.getmousepos()
  local src = drag_src
  drag_src = nil
  if mp.line == 0 then return end
  if src and mp.line > 0 then
    local target = node_at(mp.line)
    if target and src.absolute_path and target.absolute_path
       and target.absolute_path ~= src.absolute_path then
      return drop(src, target)
    end
  end
  local api = require("nvim-tree.api")
  local node = api.tree.get_node_under_cursor()
  if not node then return end
  -- open.edit on a folder toggles it, on a file opens it through the
  -- window_picker excludes -- one click for both, no double-click folklore
  api.node.open.edit(node)
end

-- Buffer-local extras on top of nvim-tree's stock keymap. Buffer-local is
-- load-bearing: suite_options asserts the GLOBAL mouse maps stay exactly as
-- the mouse section left them, and nothing here may show up there.
function M.attach(bufnr)
  require("nvim-tree.api").config.mappings.default_on_attach(bufnr)
  vim.keymap.set("n", "<LeftRelease>", tree_click, { buffer = bufnr, silent = true })
  -- deliberately NOT re-fed to the built-in: the default drag grows a
  -- character-wise selection across tree rows, which is noise here
  vim.keymap.set("n", "<LeftDrag>", tree_drag, { buffer = bufnr, silent = true })

  -- Window-local dressing, scheduled: on_attach runs while nvim-tree is
  -- still assembling the window, and bufwinid needs the finished layout.
  vim.schedule(function()
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then return end
    -- global virtualedit=all is the click-anywhere ghost space; in a tree it
    -- would let the caret float past the end of a filename
    vim.wo[win].virtualedit = "none"
    vim.wo[win].winbar = TOOLBAR
  end)
end

function M.toggle()
  if M.error then
    vim.notify(M.error, vim.log.levels.WARN)
    return
  end
  -- The tree roots at the folder of the file you are IN, not at the shell's
  -- working directory. drill launches nvim from wherever the shell happened
  -- to be -- `d lld-prac main` in your home directory used to open a tree of
  -- ~, which is a tree of everything except your project. The file's folder
  -- is the project; that is what the sidebar is for. No real file under the
  -- caret (the netrw listing, a scratch buffer): fall back to the cwd.
  --
  -- focus=false: the sidebar appears, the caret stays in your code -- the
  -- mouse is how you enter the tree. type_here() on both directions, so the
  -- toggle keeps drill's one promise: wherever you land, you are typing.
  local opts = { focus = false }
  local f = vim.fn.expand("%:p")
  if vim.bo.buftype == "" and f ~= "" and vim.fn.filereadable(f) == 1 then
    opts.path = vim.fn.fnamemodify(f, ":h")
    opts.find_file = true               -- ...and land highlighted on the file
  end
  require("nvim-tree.api").tree.toggle(opts)
  host.type_here()
end

return M
