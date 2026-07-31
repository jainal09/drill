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
vim.opt.mouse = "a"                    -- click + select + scroll
-- Click ANYWHERE, including where there is no text. Without this the caret can
-- only go where a character already is, so a click on a blank line snaps to
-- column 1 and a click to the right of a short line snaps to its end -- in a
-- half-written drill file, which is mostly blank lines and 20-character lines,
-- almost every click lands nowhere near the pointer and the mouse reads as
-- broken. Measured on a real scratch file: 9 of its 22 lines were empty.
-- Typing in that empty space pads with spaces, so clicking out to an indent
-- level on a blank line and writing there does the obvious thing.
vim.opt.virtualedit = "all"
vim.opt.clipboard = "unnamedplus"      -- system clipboard (macOS: pbcopy/pbpaste)

-- One cursor everywhere you type. Nvim's default is a vertical bar in insert
-- (i-ci-ve:ver25) but a BLOCK in terminal mode, so the caret changed shape every
-- time <C-e> moved you between the file and the interpreter -- in an editor whose
-- whole premise is that you are always typing, that reads as two different
-- states. Only the SHAPE changes: the blink and the TermCursor highlight are
-- what tell you python is still live, so they are carried over untouched.
--
-- The t: entry is REWRITTEN rather than appended. Appending leaves two t: parts
-- and relies on later-wins, which :help guicursor never actually promises (it
-- documents the precedence of "a" and nothing else). Rewriting leaves exactly
-- one answer in the option.
do
  local parts, done = {}, false
  for part in vim.o.guicursor:gmatch("[^,]+") do
    local modes, args = part:match("^([^:]+):(.*)$")
    local is_term = false
    if modes then
      for m in modes:gmatch("[^%-]+") do if m == "t" then is_term = true end end
    end
    if is_term then
      -- swap the shape token, keep blinkon/blinkoff/highlight exactly as they were
      part, done = modes .. ":" .. args:gsub("^[^%-]+", "ver25", 1), true
    end
    parts[#parts + 1] = part
  end
  if not done then                                   -- no t: entry in this nvim
    parts[#parts + 1] = "t:ver25-blinkon500-blinkoff500-TermCursor"
  end
  vim.o.guicursor = table.concat(parts, ",")
end

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
-- Copy WITHOUT losing the selection. The obvious spelling, '"+ygv', cannot work:
-- y ENDS visual mode, so gv has to put it back, and in Select mode the round
-- trip needs <C-g> either side. Feeding those keys is what typed a literal "gv"
-- into the buffer -- this config's deferred :startinsert can land mid-sequence,
-- and from Insert mode "gv" is just two characters. A Lua callback never
-- changes mode at all, so there is nothing to restore.
local function copy_selection()
  local m = vim.fn.mode(1):sub(1, 1)
  local rt = "v"                                   -- charwise
  if m == "V" or m == "S" then rt = "V"            -- linewise
  elseif m == "\22" or m == "\19" then rt = "b" end -- blockwise
  local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
  local ok, txt = pcall(vim.fn.getregion, a, b,
                        { type = rt, exclusive = vim.o.selection == "exclusive" })
  if not ok then                                   -- older nvim: no 'exclusive' opt
    ok, txt = pcall(vim.fn.getregion, a, b, { type = rt })
  end
  if ok and type(txt) == "table" and #txt > 0 then
    vim.fn.setreg("+", txt, rt)
    vim.fn.setreg('"', txt, rt)
  end
end
map({ "x", "s" }, "<C-c>", copy_selection, S)  -- copy, selection stays put
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

-- ...and the highlight goes away the moment you start typing again.
-- 'hlsearch' is ON by default in nvim and this config never set it, so every
-- match stayed lit -- through the edit, and the next one, and the one after --
-- until you happened to run another search. Every other editor drops the
-- highlight as soon as you get back to work, and here there is nothing to turn
-- it off with: :nohlsearch is a command, and reaching the command line means
-- leaving the insert mode you are supposed to live in.
--
-- InsertEnter is the honest moment: while you are still in Normal after the
-- search the matches stay lit, so <C-f> is usable and n / N still walk them
-- with the highlight on. Go back to typing and it clears.
--
-- CONFLICT 8: it has to be DEFERRED, and both spellings need it. Clearing the
-- highlight from inside the autocmd itself does nothing at all -- an autocmd
-- runs inside a save/restore of the search state, so the assignment is put back
-- on the way out. Measured, with the naive version installed:
--     [InsertEnter] set v:hlsearch = 0 -> reads back 0
--     [InsertLeave] v:hlsearch = 1          <- restored behind your back
-- vim.schedule lands the write after that context has unwound, where it sticks.
-- (:nohlsearch has exactly the same problem and exactly the same fix; neither
-- spelling is the "working" one on its own.)
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function() vim.schedule(function() vim.v.hlsearch = 0 end) end,
})

-- ---------------------------------------------------------------------------
-- toggle comment on line(s)  --  Ctrl+/
--
-- Three separate things were wrong before, and all three had to be fixed:
--   1. THE KEY. Ctrl+/ has no legacy control byte, so a terminal sends it EITHER
--      as 0x1F (nvim spells that <C-_>) OR, when the kitty/CSI-u keyboard
--      protocol is negotiated, as ESC [ 47 ; 5 u (nvim spells that <C-/>).
--      Those are two different keys -- "\31" vs "\128\252\4/" -- not aliases:
--      a <C-_> mapping is NEVER reached by <C-/>. iTerm2 3.6.10 + nvim 0.12.4
--      do negotiate CSI-u, so on this machine only <C-/> arrives; unmapped, its
--      Ctrl was stripped and the bare "/" fell into the printable-key Select
--      map below and replaced the selection. Bind BOTH (plus <C-S-/>).
--   2. THE MODE. This editor opens every file with :startinsert, so a toggle
--      bound only to n/x/s can never be reached. "i" is mandatory. And <Space>
--      is unusable as a leader here for the same reason: char 32 is in the
--      printable-key Select loop, so <leader>/ eats the selection on the Space.
--   3. THE RANGE. '< and '> are only written when you LEAVE visual/select mode.
--      Read inside a mapping they still describe the PREVIOUS selection, which
--      is why the toggle kept commenting text that was selected a moment ago.
--      line("v") (anchor) and line(".") (cursor) are live; use those.
-- Everything below is buffer-API only: no :normal!, no mode changes, nothing
-- typed. That is what keeps the selection -- and Insert mode -- intact.
-- ---------------------------------------------------------------------------

-- 'commentstring' is "# %s" for python, "-- %s" for lua, "<!-- %s -->" for html.
-- A buffer with none at all (a plain .txt) falls back to "#".
local function comment_parts()
  local cs = vim.bo.commentstring
  if type(cs) ~= "string" or not cs:find("%%s") then cs = "# %s" end
  local l, r = cs:match("^(.-)%%s(.*)$")
  l, r = vim.trim(l or ""), vim.trim(r or "")
  if l == "" then l = "#" end
  return l, r
end

-- "#" and "--" and "<!--" all contain Lua pattern metacharacters.
local function lit(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")) end

local VISUAL_OR_SELECT = {
  v = true, V = true, ["\22"] = true,   -- \22 = 0x16 = CTRL-V, visual blockwise
  s = true, S = true, ["\19"] = true,   -- \19 = 0x13 = CTRL-S, select blockwise
}

-- The LIVE line span, the mode it came from, and "is there a selection".
-- selection=exclusive means a selection that stops at column 1 of a line covers
-- NOTHING on that line -- shift+down once highlights only the line you started
-- on -- so that line is not commented either. Exactly the lines you can see
-- highlighted are the lines that change. (Only charwise: a blockwise selection
-- at column 1 really is one column wide, and linewise has no columns at all.)
local function live_range()
  local m = vim.fn.mode(1):sub(1, 1)
  if not VISUAL_OR_SELECT[m] then
    local l = vim.fn.line(".")
    return l, l, false, m
  end
  local al, ac = vim.fn.line("v"), vim.fn.col("v")
  local cl, cc = vim.fn.line("."), vim.fn.col(".")
  local lo, hi, hicol
  if al < cl or (al == cl and ac <= cc) then lo, hi, hicol = al, cl, cc
  else lo, hi, hicol = cl, al, ac end
  if (m == "v" or m == "s") and vim.o.selection == "exclusive"
     and hi > lo and hicol == 1 then
    hi = hi - 1
  end
  return lo, hi, true, m
end

local function toggle_comment()
  -- the REPL split is a terminal buffer: 'modifiable' is off there, and you can
  -- be sitting in it in Normal mode (<C-w>k, or the mouse). Without this guard
  -- Ctrl+/ raises E5108 "Buffer is not 'modifiable'" at you.
  if not vim.bo.modifiable then return end

  local lo, hi, selecting, mode = live_range()
  local lines = vim.api.nvim_buf_get_lines(0, lo - 1, hi, false)
  if #lines == 0 then return end

  local left, right = comment_parts()
  local open  = left .. " "
  local close = right ~= "" and (" " .. right) or ""

  -- Which lines actually get touched: the ones with code on them. A blank line
  -- inside a block is left alone, so a round trip is byte-for-byte exact and
  -- you do not get trailing "# " litter. (If the whole range is blank there is
  -- nothing to skip, so every line counts -- Ctrl+/ on an empty line still
  -- starts a comment for you.)
  local idx = {}
  for i, l in ipairs(lines) do if l:find("%S") then idx[#idx + 1] = i end end
  if #idx == 0 then for i = 1, #lines do idx[i] = i end end

  -- ONE indent for the whole block: the smallest one. Per-line indentation
  -- would break the column alignment of nested code the moment you uncomment.
  local pad
  for _, i in ipairs(idx) do
    local ws = lines[i]:match("^[ \t]*")
    if pad == nil or #ws < #pad then pad = ws end
  end
  pad = pad or ""

  -- Mixed block rule: uncomment ONLY if every code line is already commented;
  -- one bare line anywhere and the whole block gets commented. That is what
  -- makes Ctrl+/ twice a guaranteed no-op on any block, mixed or not -- the
  -- first press always lands the block in a uniform state.
  local commented = "^[ \t]*" .. lit(left)
  local uncomment = true
  for _, i in ipairs(idx) do
    if not lines[i]:find(commented) then uncomment = false break end
  end

  local function apply(l)
    if not uncomment then
      -- l:sub(1, #pad), NOT pad: every touched line has at least #pad leading
      -- whitespace, but it may not be the SAME whitespace. Splicing the block's
      -- pad string in would rewrite this line's own indent -- with a tab line
      -- and an 8-space line in one block that silently turned "        y = 1"
      -- into "\t       y = 1". Reuse the line's own bytes and the round trip
      -- stays exact.
      return l:sub(1, #pad) .. open .. l:sub(#pad + 1) .. close
    end
    l = (l:gsub("^([ \t]*)" .. lit(left) .. "[ \t]?", "%1", 1))
    if right ~= "" then l = (l:gsub("[ \t]?" .. lit(right) .. "[ \t]*$", "", 1)) end
    return l
  end

  local shift = {}                        -- per-line character delta
  for i = 1, #lines do shift[i] = 0 end
  for _, i in ipairs(idx) do
    local new = apply(lines[i])
    shift[i] = #new - #lines[i]
    lines[i] = new
  end
  vim.api.nvim_buf_set_lines(0, lo - 1, hi, false, lines)

  -- Keep the caret on the same CHARACTER. The edit is a pure insert/delete at
  -- character offset #pad, so anything at or past that offset moves by the
  -- line's delta. Nothing here leaves Insert mode -- a Lua-callback mapping
  -- does not change mode -- so the user is still typing, one marker along.
  --
  -- With a CHARWISE selection this is also what keeps the text you highlighted
  -- inside the highlight: the anchor cannot be moved (setpos("v", ...) raises
  -- E474), so moving the cursor end is the closest reachable answer. Skipped
  -- for LINEWISE (columns are irrelevant) and BLOCKWISE (the column IS the
  -- block width -- shifting it would silently widen your block).
  if (not selecting) or mode == "v" or mode == "s" then
    local pos = vim.api.nvim_win_get_cursor(0)
    local row, col = pos[1], pos[2]       -- col is 0-based
    if row >= lo and row <= hi then
      if col >= #pad then col = col + (shift[row - lo + 1] or 0) end
      local len = #(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or "")
      if col < 0 then col = 0 elseif col > len then col = len end
      pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
    end
  end
end

-- "x" and "s" are registered separately and never as "v": one combined "v"
-- mapping makes nvim switch Select -> Visual BEFORE the callback runs.
-- Deliberately NOT bound in "t" (terminal), so Ctrl+/ still reaches python in
-- the <C-e> REPL split, nor in "c" (cmdline).
for _, key in ipairs({ "<C-_>", "<C-/>", "<C-S-/>" }) do
  for _, mode in ipairs({ "n", "i", "x", "s" }) do
    map(mode, key, toggle_comment, S)
  end
end

-- ---------------------------------------------------------------------------
-- Tab / Shift+Tab indent a selection  --  selection ONLY
--
-- Bound in "x" and "s" and deliberately NOWHERE ELSE. In insert mode Tab has to
-- go on inserting indentation -- you are writing Python -- and in normal mode it
-- is the jumplist. Tab is 0x09, outside the 32..126 printable-key Select loop
-- below, so there is nothing to fight over here.
--
-- Not vim's own :{range}> , which was the obvious answer and is wrong: an ex
-- command DROPS Select mode, so the first Tab works and a second one silently
-- shifts only the line the cursor happens to be on. Measured -- two Tabs on a
-- 2-line selection indented one line by 8 and the other by 4. Same buffer-API
-- rule as the comment toggle: touch the lines, never the mode.
--
-- Widths are computed in DISPLAY columns, not bytes, so a tab counts as a full
-- tabstop. Re-rendering the indent through 'expandtab' means a leading tab in a
-- spaces buffer becomes spaces -- that is not a round-trip loss, it is exactly
-- what :> does, verified byte-for-byte against it.
-- ---------------------------------------------------------------------------
local function shift_lines(dir)                  -- dir = 1 indent, -1 unindent
  if not vim.bo.modifiable then return end
  local lo, hi = live_range()
  local sw, ts = vim.fn.shiftwidth(), vim.bo.tabstop
  if sw <= 0 then sw = ts end                    -- shiftwidth=0 means "use tabstop"
  local et = vim.bo.expandtab
  local lines = vim.api.nvim_buf_get_lines(0, lo - 1, hi, false)
  if #lines == 0 then return end

  local function width(ws)                       -- display width of an indent
    local w = 0
    for ch in ws:gmatch(".") do
      if ch == "\t" then w = w + (ts - w % ts) else w = w + 1 end
    end
    return w
  end
  local function make(w)                         -- an indent of display width w
    if et then return string.rep(" ", w) end
    return string.rep("\t", math.floor(w / ts)) .. string.rep(" ", w % ts)
  end

  local shift = {}
  for i, l in ipairs(lines) do
    shift[i] = 0
    if l:find("%S") then                         -- blank lines stay blank: no
      local ws = l:match("^[ \t]*")              -- trailing-whitespace litter
      local w = width(ws)
      local new = make(dir > 0 and w + sw or math.max(0, w - sw)) .. l:sub(#ws + 1)
      shift[i] = #new - #l
      lines[i] = new
    end
  end
  vim.api.nvim_buf_set_lines(0, lo - 1, hi, false, lines)

  -- same caret rule as the comment toggle: stay on the character you were on.
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2]
  if row >= lo and row <= hi then
    col = math.max(0, col + (shift[row - lo + 1] or 0))
    local len = #(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or "")
    if col > len then col = len end
    pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
  end
end
map({ "x", "s" }, "<Tab>",   function() shift_lines(1) end, S)
map({ "x", "s" }, "<S-Tab>", function() shift_lines(-1) end, S)

-- CONFLICT 3: <C-z> is suspend by default. Mapped in every mode that can reach
-- nvim's own suspend, so the editor cannot be accidentally backgrounded.
map({ "n", "v", "i" }, "<C-z>", "<Cmd>undo<CR>", S)
map({ "n", "v", "i" }, "<C-y>", "<Cmd>redo<CR>", S)
-- Ctrl+Shift+Z is the redo every other editor uses, and it only exists at all
-- because of CSI-u: in the legacy encoding Shift is dropped from a control chord,
-- so Ctrl+Shift+Z and Ctrl+Z are both 0x1A and cannot be told apart. With the
-- protocol negotiated they are separate keys -- "\128\252\2\26" vs "\26" -- so
-- this is a real mapping, not a duplicate. On a terminal that speaks no CSI-u it
-- degrades to <C-z> and undoes instead; <C-y> is the redo that always works.
map({ "n", "v", "i" }, "<C-S-z>", "<Cmd>redo<CR>", S)

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

-- ---------------------------------------------------------------------------
-- Click anywhere and carry on typing  --  <LeftRelease>
--
-- 'mouse=a' already moves the caret to the click, and from INSERT mode that is
-- the whole story: click, keep typing. From NORMAL mode it is half the story --
-- the caret lands where you clicked but you are still in Normal, so the next
-- letter runs as a command. Measured: click a line, type "x", and it DELETED a
-- character instead of typing one. Normal mode is one <C-c> away at all times
-- (<C-c> is Esc in insert), so this is reachable by accident, not just by
-- someone who asked for vim.
--
-- <LeftRelease>, not <LeftMouse>. Two reasons, and the second is the important
-- one:
--   * the PRESS is what moves the caret. Mapping it would mean re-implementing
--     the move; mapping the release lets the built-in do it and just adds the
--     mode change afterwards.
--   * a mouse DRAG has already switched to Select mode (selectmode=mouse) by
--     the time the button comes up, so drag-select keeps working untouched.
--
-- Bound in "n" and in "x"/"s" (see the jitter note below), never in:
--   i    already lands you typing at the click; there is nothing to add.
--   t    the interpreter. Arriving there is already handled by the WinEnter
--        rule below, and a click INSIDE it is you reading scrollback -- being
--        yanked back to the prompt is the opposite of what you asked for.
-- ---------------------------------------------------------------------------

-- a buffer you can actually type in. netrw is the `d`-with-no-argument
-- directory listing: buftype is empty there too, but every letter is a command.
local function typing_buffer()
  return vim.bo.buftype == "" and vim.bo.modifiable and vim.bo.filetype ~= "netrw"
end

local function click_and_type()
  if not typing_buffer() then return end
  -- Plain :startinsert, and deliberately NOT :startinsert! -- with
  -- virtualedit=all the press has already put the caret at the exact column
  -- you clicked, empty space included, and `!` is `A`, which would yank it
  -- back to the end of the line and throw that away. There is nothing left to
  -- correct here: the only job is to leave you typing.
  vim.cmd("startinsert")
end
map("n", "<LeftRelease>", click_and_type, S)

-- ---------------------------------------------------------------------------
-- A click that JITTERED. This is the one that actually breaks the mouse.
--
-- A finger on a trackpad never holds still. Press, and the pointer drifts a few
-- pixels before the button comes up, so the terminal reports a MOTION event
-- (SGR button+32) in between. A character cell is about 8px wide, so drifting
-- across one cell boundary is the common case, not the rare one -- and
-- selectmode=mouse turns any motion-with-button-down into a SELECTION. Measured
-- under the real config:
--
--     press, release, nothing between        -> mode i, typing        (fine)
--     press, motion in the SAME cell, release-> mode i, typing        (fine)
--     press, motion ONE cell over, release   -> mode s, SELECT        (broken)
--     press, motion out and back, release    -> mode s, SELECT        (broken)
--
-- So the caret is in the right place but you are stranded in Select mode
-- holding a one-character selection you never asked for, the Normal-mode
-- mapping above cannot fire, and the next letter you type REPLACES a character
-- instead of inserting one. Every synthetic test passed because a script clicks
-- perfectly still; a hand never does.
--
-- The rule: if the pointer ended up within ONE CELL of where it went down --
-- in BOTH axes -- it was a click, not a drag. Collapse it and carry on typing.
-- Nobody drag-selects a single character with a mouse; that is what
-- shift+arrows and double-click are for, and both still work. A deliberate drag
-- (two cells or more, or two rows or more) is left completely alone.
--
-- BOTH axes, and the row half is not hypothetical. A pointer resting near a row
-- boundary drifts DOWN a row just as easily as it drifts sideways, and that
-- case is far worse than the sideways one: the selection then runs from the
-- press column on one line to the same column on the next, so it covers the
-- whole tail of one line and the head of the next. Measured -- one jittered
-- click plus one keystroke turned "        total += i" and "    return total"
-- into the single line "        toZ total". A click the user believed did
-- nothing but move the caret destroyed a line and a half.
--
-- The caret goes to the PRESS cell, not the release cell: the press is where
-- you aimed, the drift is the accident. cursor() takes a third argument for the
-- virtualedit offset, which is what carries a click in empty space across
-- intact -- nvim_win_set_cursor cannot express one.
-- ---------------------------------------------------------------------------
local function release_collapse()
  if not typing_buffer() then return end
  local a, c = vim.fn.getpos("v"), vim.fn.getpos(".")   -- {buf, line, col, off}
  if math.abs(c[2] - a[2]) > 1 then return end          -- >1 row: a real drag
  local av, cv = a[3] + (a[4] or 0), c[3] + (c[4] or 0)
  if math.abs(cv - av) > 1 then return end              -- >1 cell across: a real drag
  -- Leaving Select/Visual is the one thing here that has to be a real mode
  -- change -- there is no buffer-API way out of it -- so <Esc> is fed and the
  -- caret is put back afterwards, on the next tick, once the mode has settled.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
                        "n", false)
  vim.schedule(function()
    if not typing_buffer() then return end
    pcall(vim.fn.cursor, a[2], a[3], a[4] or 0)
    vim.cmd("startinsert")
  end)
end
map({ "x", "s" }, "<LeftRelease>", release_collapse, S)

-- ...and the same click with OPTION held. This is not a nicety: on macOS,
-- Option+click is how iTerm2 itself moves the cursor at a shell prompt, so it
-- is reflex, and holding Option is also the advice for grabbing the terminal's
-- own selection. Vim gives ALT-LeftMouse a different job -- it starts a
-- BLOCKWISE selection (:help mouse-using) -- so an Option+click put the caret
-- in the right place and then left you sitting in a one-cell block, where the
-- next key is a block operator instead of a letter. It looks like the click
-- did nothing.
--
-- Captured off iTerm2 with tests/mousecheck.sh: the press arrives as
-- ESC[<8;col;row M -- button 0 with the Alt bit (8) set in the SGR modifier
-- field, Shift being 4 and Ctrl 16 -- and nvim spells that <M-LeftMouse>.
--
-- CTRL is dropped for the same reason, and its failure is the loudest of the
-- lot: nvim maps <C-LeftMouse> to CTRL-] , a tag jump (:help mouse-using). This
-- editor has no tags file and never will -- no LSP, no plugins -- so a Ctrl+click
-- raises "E426: Tag not found" and then WEDGES the editor behind a modal
-- "Press ENTER or type command to continue" prompt. One stray Ctrl and the
-- mouse appears to have hung the whole thing.
--
-- So Option and Ctrl are simply dropped for the left button: press, drag and
-- release all do what the unmodified ones do. Nothing is lost -- <C-q> is still
-- how you ask for a blockwise selection on purpose, and the tag jump was never
-- reachable here anyway. SHIFT (4) is deliberately left alone: shift+click
-- extending a selection is what every other editor does too.
for _, m in ipairs({ "n", "i", "x", "s" }) do
  for _, mod in ipairs({ "M", "C" }) do
    map(m, "<" .. mod .. "-LeftMouse>", "<LeftMouse>", S)
    map(m, "<" .. mod .. "-LeftDrag>",  "<LeftDrag>",  S)
  end
end
-- The release goes to the SAME handlers as an unmodified one, not to a
-- non-remapped "<LeftRelease>" -- that would reach nvim's built-in and skip the
-- jitter collapse, so an Option+click that drifted would still strand you in
-- Select mode.
for _, mod in ipairs({ "M", "C" }) do
  map("i", "<" .. mod .. "-LeftRelease>", "<LeftRelease>", S)
  map("n", "<" .. mod .. "-LeftRelease>", click_and_type, S)   -- a plain click
  map({ "x", "s" }, "<" .. mod .. "-LeftRelease>", release_collapse, S)
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
    elseif typing_buffer() then
      vim.cmd("startinsert")
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
