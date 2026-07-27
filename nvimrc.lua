-- ~/drill/nvimrc.lua -- isolated drill editor. Load ONLY via: nvim -u ~/drill/nvimrc.lua
-- Syntax highlighting only. No completion, no LSP, no snippets, no plugins, no AI.
vim.opt.runtimepath:remove(vim.fn.stdpath("data") .. "/site")
vim.g.mapleader = " "
vim.cmd("syntax on")
vim.cmd("filetype plugin indent on")
-- nvim's DEFAULT colorscheme paints Statement/PreProc/Number/Type all the same
-- near-white (#e0e2ea) and only bolds keywords. Built-in, no plugin. Swap freely:
-- habamax | wildcharm | retrobox | sorbet | slate | desert
vim.opt.termguicolors = true
vim.cmd("colorscheme habamax")

vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.undofile = false
vim.opt.mouse = "a"                    -- select + scroll
vim.opt.clipboard = "unnamedplus"      -- system clipboard (macOS: pbcopy/pbpaste)

-- shift+arrows select, the way every other editor does it. Three options, and
-- all three are needed:
--   keymodel=startsel   a SHIFTED cursor key starts a selection
--           ,stopsel    an UNshifted one clears it again
--   selectmode=key,mouse  that selection is SELECT mode, where the next key you
--                       type REPLACES it. (Plain Visual would run it as a
--                       command: type "a" over a selection and you'd get append.)
--   selection=exclusive the cursor sits just past the last selected character,
--                       which is what the arrow keys imply on screen.
vim.opt.keymodel = "startsel,stopsel"
vim.opt.selectmode = "key,mouse"
vim.opt.selection = "exclusive"

-- CONFLICT 5: completion off at every source. This is what frees <C-x> for cut.
-- ('omnifunc = ""' IS the disabled state; the literal string "none" would be
--  treated as a function name and raise E117 instead of a clean E764.)
vim.opt.completeopt = ""
vim.opt.complete = ""
vim.opt.omnifunc = ""
vim.opt.completefunc = ""
vim.opt.dictionary = ""
vim.opt.thesaurus = ""
vim.opt.infercase = false
vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
  callback = function() vim.bo.omnifunc = ""; vim.bo.completefunc = "" end,
})

local map = vim.keymap.set
local S = { silent = true }
local L = { silent = false }           -- loud: the cmdline prompt must stay visible

-- save. CONFLICT 1: `stty -ixon` (in drill.zsh) stops the tty eating ^S as XOFF.
local function save()
  if vim.bo.buftype ~= "" then return end   -- netrw / terminal buffer: nothing to save
  vim.cmd("write")                          -- real write errors still surface
end
map({ "n", "v", "i" }, "<C-s>", save, S)

-- From here on "x" means visual ONLY and "s" means select ONLY -- plain "v"
-- would be both, and Select mode needs its own version of nearly everything:
-- there an unmapped RHS gets typed INTO the selection, so a bare `"+y` would
-- replace your text with a quote mark. <C-g> flips Select -> Visual first.

-- CONFLICT 4: <C-c> is remapped ONLY in visual/select and insert. Normal and
-- terminal mode are left alone, so SIGINT still reaches anything running in a
-- terminal split.
map("x", "<C-c>", '"+ygv', S)            -- copy to system clipboard, keep selection
map("s", "<C-c>", '<C-g>"+ygv<C-g>', S)  -- copy in select mode, stay in select
map("i", "<C-c>", "<Esc>", S)          -- stays Esc, as asked

map("x", "<C-x>", '"+d', S)            -- cut
map("s", "<C-x>", '<C-g>"+d', S)

map("n", "<C-v>", '"+p', S)            -- paste
map("i", "<C-v>", "<C-r><C-o>+", S)    -- <C-o> = insert literally, no re-indent
map("c", "<C-v>", "<C-r>+", L)
map("x", "<C-v>", '"_c<C-r><C-o>+', S)       -- paste OVER a selection, and `"_c`
map("s", "<C-v>", '<C-g>"_c<C-r><C-o>+', S)  -- keeps the clipboard intact

-- CONFLICT 2: visual block moves off <C-v> to <C-q>. `stty -ixon` also frees ^Q
-- (the one flag disables both XOFF/^S and XON/^Q).  noremap => the ORIGINAL <C-v>.
map({ "n", "x" }, "<C-q>", "<C-v>", S)

-- select all. `gH` starts LINEWISE SELECT mode and <C-o>G runs one normal-mode
-- command (G) without leaving it, so you end up with the file selected and
-- still effectively typing: the next character replaces the lot. The old
-- `ggVG` left you in Visual mode, where every letter is a command instead.
map("n", "<C-a>", "gggH<C-o>G", S)
map("i", "<C-a>", "<C-o>gg<C-o>gH<C-o>G", S)

map("n", "<C-f>", "/", L)              -- find
map("i", "<C-f>", "<Esc>/", L)

-- toggle comment on line(s)
local toggle_comment = function()
  local start = vim.fn.getpos("'<")[2]
  local finish = vim.fn.getpos("'>")[2]
  if start == nil then start = vim.fn.line(".") end
  if finish == nil then finish = vim.fn.line(".") end
  for lnum = start, finish do
    local line = vim.fn.getline(lnum)
    if vim.fn.match(line, "^\\s*#") == 0 then
      vim.fn.setline(lnum, vim.fn.substitute(line, "^\\(\\s*\\)# ?", "\\1", ""))
    else
      vim.fn.setline(lnum, vim.fn.substitute(line, "^\\(\\s*\\)", "\\1# ", ""))
    end
  end
end

-- Ctrl+/ - try both possible keycodes with noremap to skip char replacement
vim.keymap.set("n", "<C-_>", toggle_comment, S)
vim.keymap.set("x", "<C-_>", toggle_comment, S)
-- For select mode, exit to visual, toggle, stay visual
vim.keymap.set("s", "<C-_>", function()
  vim.cmd("normal! \\<C-g>")
  toggle_comment()
end, S)

-- CONFLICT 3: <C-z> is suspend by default. Mapped in every mode that can reach
-- nvim's own suspend, so the editor cannot be accidentally backgrounded.
map({ "n", "v", "i" }, "<C-z>", "<Cmd>undo<CR>", S)
map({ "n", "v", "i" }, "<C-y>", "<Cmd>redo<CR>", S)

-- CONFLICT 6: on a Mac the big key labelled "delete" sends <BS>; <Del> is
-- fn+delete. Mapping only <Del> is why Ctrl+A then delete did nothing -- <BS>
-- in Visual mode just walks the selection back one character.
-- `"_c` not `"_d`: deleting a selection in a normal editor leaves you typing
-- where it was. Black-holed for the same reason as `x`: with
-- clipboard=unnamedplus a plain delete would overwrite whatever you last
-- copied from the browser.
map("n", "<Del>", '"_x', S)
for _, k in ipairs({ "<Del>", "<BS>" }) do
  map("x", k, '"_c', S)
  map("s", k, '<C-g>"_c', S)           -- insert-mode <BS>/<Del> are already right
end

-- ...and the same for typing over a selection. Select mode replaces it for
-- free, but the replaced text would land in the system clipboard, so every
-- printable key goes through the black hole too.
-- Three of them must be spelled by name, not as themselves: a literal trailing
-- space is STRIPPED off the right-hand side of a mapping (which silently made
-- the space key delete a selection and type nothing), and < and | would each
-- start being parsed as notation.
local NAMED = { [32] = "<Space>", [60] = "<lt>", [124] = "<Bar>" }
for i = 32, 126 do
  local k = NAMED[i] or string.char(i)
  map("s", k, '<C-g>"_c' .. k, S)
end

-- run / interpreter. <C-e> is the whole interface: it shows the interpreter and
-- it hides it, from any mode, and you are always typing wherever you land.
local RUN_H = 15
local last_file = nil
local out_win = nil                      -- plain-run window: throwaway, reused
local repl_win, repl_buf = nil, nil      -- the python3 -i session
local repl_file, repl_tick = nil, nil    -- the code that session was started FROM

-- CONFLICT 7: `:startinsert` is IGNORED when it runs inside a mapping that was
-- invoked from insert mode -- nvim restores the mapping's original mode on the
-- way out and clobbers it. Since <C-e> is pressed mid-typing, every insert has
-- to be deferred past the end of the mapping. That is what vim.schedule buys.
local function type_here()
  vim.schedule(function()
    if vim.bo.buftype == "terminal" then
      -- jobwait(...,0) == -1 means still running. Entering terminal mode on a
      -- FINISHED process is a trap: the next key just closes the window.
      local id = vim.b.terminal_job_id
      if id and vim.fn.jobwait({ id }, 0)[1] == -1 then vim.cmd("startinsert") end
    elseif vim.bo.buftype == "" and vim.bo.modifiable
       and vim.bo.filetype ~= "netrw" then            -- `d` with no arg: a listing,
      vim.cmd("startinsert")                          -- where every letter is a command
    end
  end)
end

local function shows(win, buf)
  return win and buf and vim.api.nvim_win_is_valid(win)
     and vim.api.nvim_win_get_buf(win) == buf
end

-- ":update" writes only when the buffer is actually dirty, so b:changedtick is
-- an honest answer to "has the code moved on since python read it?".
local function source_state()
  if vim.bo.buftype ~= "" then return last_file, repl_tick end   -- not a file: no news
  vim.cmd("silent update")
  last_file = vim.fn.expand("%:p")
  return last_file, vim.b.changedtick
end

-- plain run: fresh process every time, one window reused.
local function run_once()
  vim.cmd("stopinsert")
  local f = source_state()
  if not f then return end                             -- nothing run yet
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    vim.api.nvim_win_close(out_win, true)              -- reuse, don't stack splits
  end
  vim.cmd("botright " .. RUN_H .. "split | terminal python3 " .. vim.fn.shellescape(f))
  out_win = vim.api.nvim_get_current_win()
end

-- start python on the current code, reusing the split if one is already there.
local function repl_spawn(f, tick)
  local stale = repl_buf
  if shows(repl_win, stale) then
    vim.api.nvim_set_current_win(repl_win)             -- swap in place, no flicker
  else
    vim.cmd("botright " .. RUN_H .. "split")
  end
  vim.cmd("terminal python3 -i " .. vim.fn.shellescape(f))
  repl_win, repl_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  repl_file, repl_tick = f, tick
  if stale and stale ~= repl_buf and vim.api.nvim_buf_is_valid(stale) then
    vim.api.nvim_buf_delete(stale, { force = true })   -- and kill the old python
  end
  type_here()
end

-- show: the interpreter always has the code you can see. Edited since it
-- started? Restart it. Untouched? Same session, so whatever you were poking at
-- in the REPL is still there.
local function repl_show()
  vim.cmd("stopinsert")
  local f, tick = source_state()
  if not f then return end
  if not (repl_buf and vim.api.nvim_buf_is_valid(repl_buf))
     or f ~= repl_file or tick ~= repl_tick then
    return repl_spawn(f, tick)
  end
  if shows(repl_win, repl_buf) then
    vim.api.nvim_set_current_win(repl_win)
  else
    vim.cmd("botright " .. RUN_H .. "split")           -- hidden: bring it back
    vim.api.nvim_win_set_buf(0, repl_buf)
    repl_win = vim.api.nvim_get_current_win()
  end
  type_here()
end

local function repl_hide()
  if shows(repl_win, repl_buf) then
    vim.api.nvim_win_hide(repl_win)                    -- window gone, python untouched
  end
  type_here()                                          -- back in the editor, typing
end

-- ...and however else you move between the two windows (<C-w>j/k, mouse), the
-- same rule holds: land in a live terminal -> at the prompt; land back on the
-- file -> in insert. Only a jump FROM the interpreter re-enters insert, so
-- opening a file doesn't ambush you in insert mode.
local from_term = false
vim.api.nvim_create_autocmd("WinLeave", {
  callback = function() from_term = vim.bo.buftype == "terminal" end,
})
vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "WinEnter" }, {
  callback = function()
    if vim.bo.buftype == "terminal" then
      type_here()
    elseif from_term then
      from_term = false
      type_here()
    elseif vim.bo.buftype == "" and vim.bo.modifiable then
      type_here()
    end
  end,
})

-- CONFLICT 4 again: <C-e> is bound in terminal mode ONLY, so Ctrl+C / Ctrl+D
-- still reach python itself.
map("t", "<C-e>", repl_hide, S)

for _, m in ipairs({
  { { "n", "i" }, "<C-e>", repl_show },   { { "n", "i" }, "<C-r>", run_once },
  { "n", "<F5>", run_once },              { "n", "<leader>r", run_once },
  { "n", "<F6>", repl_show },             { "n", "<leader>i", repl_show },
}) do
  map(m[1], m[2], m[3], S)
end
