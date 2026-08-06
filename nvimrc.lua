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

-- Are we on WSL? Asked by the clipboard fallback below, and again by the quit
-- chord much further down. Both uses only ever ADD a fallback, so on macOS and
-- on a normal Linux box every one of them is dead code.
local IS_WSL = vim.env.WSL_DISTRO_NAME ~= nil
if not IS_WSL and vim.fn.filereadable("/proc/version") == 1 then
  local first = vim.fn.readfile("/proc/version", "", 1)[1] or ""
  IS_WSL = first:lower():find("microsoft") ~= nil
end

-- ...and on WSL, something to point it AT. Nvim finds a provider by itself
-- nearly everywhere -- pbcopy/pbpaste on macOS, wl-copy/xclip/xsel/win32yank on
-- Linux -- so on a Mac and on any Linux desktop this block does nothing at all.
--
-- WSL is where it earns its place. `unnamedplus` with a provider that cannot
-- reach a display does not fail loudly: Ctrl+C copies nothing, Ctrl+V pastes
-- nothing, and Ctrl+V over a SELECTION deletes it and puts nothing back, while
-- "clipboard: No provider" waits as a hit-enter prompt in an editor whose whole
-- premise is that you never stop typing. clip.exe and powershell.exe are the one
-- pair still there when interop is on but no display is.
--
-- Note WSLg supplies the display SERVER, not these clients: wl-clipboard and
-- xclip are ordinary packages you still have to install.
do
  local function have(cmd) return vim.fn.executable(cmd) == 1 end
  -- an EXPORTED-BUT-EMPTY DISPLAY="" is a string, so `~= nil` accepts it while
  -- it names no display at all
  local function set(v) return v ~= nil and v ~= "" end

  -- The nominal native provider, by name only.
  local native = nil
  for _, c in ipairs({ "pbcopy", "wl-copy", "xclip", "xsel",
                       "win32yank.exe", "lemonade", "doitclient" }) do
    if have(c) and (c ~= "wl-copy"  or set(vim.env.WAYLAND_DISPLAY))
               and (c ~= "xclip" and c ~= "xsel" or set(vim.env.DISPLAY)) then
      native = c
      break
    end
  end

  -- A display NAME is not a display. DISPLAY can be exported and stale, point
  -- at a server that is gone, or fail authorization -- and then xclip is
  -- "installed and usable" by every cheap test and still cannot move a byte.
  -- Three reviewers flagged that gap, so ask the display itself.
  --
  -- WSL only, because that is the only place with something to fall back TO,
  -- and it READS rather than writes: xclip forks a daemon to own a selection it
  -- has been given, so a write probe leaves a process behind and can block a
  -- pipeline waiting on it. A read answers the question and exits.
  --
  -- Two things this has to get right, both learned from review:
  --
  --   TIMEOUT. This runs synchronously at config load. `wl-paste` can sit
  --   waiting on a compositor that never answers, and without a bound that is
  --   not a slow editor, it is an editor that never opens. `timeout` is always
  --   present here -- this branch is WSL-only.
  --
  --   AN EMPTY CLIPBOARD IS NOT A DEAD DISPLAY. Both exit non-zero, so the
  --   exit code alone would demote a perfectly good provider on a fresh
  --   session that simply has nothing copied yet. Measured messages: a dead X
  --   display says "Can't open display", a missing compositor says "Failed to
  --   connect to a Wayland server", and an empty-but-live selection says
  --   nothing of the kind. Match on that, and treat anything unrecognised as
  --   ALIVE -- the cost of being wrong that way is one slow paste, where the
  --   other way is a silently dead clipboard.
  local function display_answers()
    local probe = ({ ["wl-copy"] = { "wl-paste", "--no-newline" },
                     ["xclip"]   = { "xclip", "-o", "-selection", "clipboard" },
                     ["xsel"]    = { "xsel", "--clipboard", "--output" } })[native]
    if not probe then return true end            -- nothing display-bound to ask
    local cmd = { "timeout", "2" }
    for _, a in ipairs(probe) do cmd[#cmd + 1] = a end
    local out = (vim.fn.system(cmd) or ""):lower()
    if vim.v.shell_error == 0 then return true end
    if vim.v.shell_error == 124 then return false end        -- timeout: no answer
    return not (out:find("can't open display") or out:find("cannot open display")
             or out:find("failed to connect")  or out:find("unable to open display"))
  end

  -- Leave nvim's own provider alone whenever it can actually work: it gets
  -- linewise/charwise register semantics right, and reimplementing that here
  -- got the trailing newline of a linewise yank wrong on the first attempt.
  -- Only when the display does not answer -- or there is no native tool at all
  -- -- take over with the pair that is always there under interop.
  if IS_WSL and have("clip.exe") and have("powershell.exe")
     and not (native and display_answers()) then
    -- Get-Clipboard returns CRLF and nvim splits on \n only, so paste has to be
    -- a Lua function: nothing built in strips the \r that would otherwise end
    -- every pasted line.
    local function from_windows()
      local out = vim.fn.systemlist({ "powershell.exe", "-NoProfile", "-NoLogo",
                                      "-Command", "Get-Clipboard" })
      if vim.v.shell_error ~= 0 then return {} end
      for i, line in ipairs(out) do out[i] = (line:gsub("\r$", "")) end
      return out
    end
    vim.g.clipboard = {
      name = "wsl-interop",
      copy  = { ["+"] = "clip.exe",   ["*"] = "clip.exe" },
      paste = { ["+"] = from_windows, ["*"] = from_windows },
      -- every paste really asks Windows. A cache would answer with what YOU
      -- last copied and silently ignore anything copied in a browser, which is
      -- most of what this register is for.
      cache_enabled = 0,
    }
  end
end

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

-- A buffer you can actually type in -- and therefore the one predicate every
-- guard in this file should be asking. It is defined here, before its first
-- use, because getting it wrong is not theoretical:
--
--   `buftype ~= ""` does NOT mean "not the directory listing". netrw's buftype
--   is EMPTY. Measured in the bare `d` listing: buftype '', modifiable 0,
--   filetype 'netrw'. So a guard written as `buftype ~= ""` sails straight
--   through netrw, and only the modifiable/filetype checks below stop it.
--
-- <C-s> used to guard that way, and pressing it in the listing raised a Lua
-- traceback and left the editor behind a modal "Press ENTER or type command to
-- continue" -- the exact failure this config went to trouble to eliminate for
-- Ctrl+click. Measured before this fix: --remote-expr blocked until a <CR>.
local function typing_buffer()
  return vim.bo.buftype == "" and vim.bo.modifiable and vim.bo.filetype ~= "netrw"
end

-- save. CONFLICT 1: `stty -ixon` (in drill.sh) stops the tty eating ^S as XOFF.
local function save()
  if not typing_buffer() then return end    -- listing / terminal: nothing to save
  vim.cmd("write")                          -- real write errors still surface
end
map({ "n", "v", "i" }, "<C-s>", save, S)

-- ---------------------------------------------------------------------------
-- Auto-save  --  so <C-s> is something you never have to remember
--
-- CONFLICT 12: the recipe everyone posts for this is an InsertLeave autocmd, and
-- in THIS config it would essentially never fire. Every other editor's autosave
-- leans on you leaving insert mode regularly; here :startinsert is the resting
-- state and you can drill for an hour without leaving it once. The event that
-- actually tracks "the code changed" while you are typing is TextChangedI.
--
-- Which is also why it has to be DEBOUNCED. TextChangedI fires on every single
-- keystroke, and writing the file per character is a syscall per character. A
-- generation counter is enough: each change schedules a write and invalidates
-- the one before it, so a burst of typing costs exactly one write, AUTOSAVE_MS
-- after you pause. vim.defer_fn, not a uv timer -- nothing to close, nothing to
-- leak, and no 0.10-only vim.uv on a config that claims to run on 0.9.
--
-- :update, not :write -- it is a no-op when the buffer is not modified, so the
-- pause after every word does not keep re-writing an unchanged file.
--
-- What it deliberately does NOT touch: the interpreter split (a terminal
-- buffer), the netrw listing, and any buffer with no filename -- :w with no
-- name raises E32, which would pop an error at you mid-keystroke. Those are the
-- same three exclusions the click handler makes, for the same reason.
-- ---------------------------------------------------------------------------
local AUTOSAVE_MS = 700
local autosave_gen = 0

local function autosave_now()
  if not typing_buffer() then return end
  if vim.api.nvim_buf_get_name(0) == "" then return end   -- unnamed: :w would E32
  if not vim.bo.modified then return end
  vim.cmd("silent! update")     -- silent!: a read-only file must not interrupt you
end

vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
  callback = function()
    autosave_gen = autosave_gen + 1
    local mine = autosave_gen
    vim.defer_fn(function()
      if mine == autosave_gen then autosave_now() end   -- still the newest? write.
    end, AUTOSAVE_MS)
  end,
})

-- ...and immediately on the way out of anything, where waiting for the debounce
-- would mean losing the last few characters you typed.
vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "FocusLost", "VimLeavePre" }, {
  callback = autosave_now,
})

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
-- Insert's <C-f> rides through Normal, and that <Esc> shifts the caret one
-- column left before the prompt even opens. Fine if the search runs -- the
-- caret goes to the match -- but the abort leg promises to put you back
-- EXACTLY where you were typing, so the pre-<Esc> spot is stashed here and
-- consumed there.
local search_from = nil
map("i", "<C-f>", function()
  search_from = vim.api.nvim_win_get_cursor(0)
  return "<Esc>/"
end, { expr = true, silent = false })

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
-- CONFLICT 11: it has to be DEFERRED, and both spellings need it. Clearing the
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
-- ...and the search tells you what to do next.
--
-- The prompt is a bare "/" with a cursor after it. Nothing on screen says that
-- Enter runs it, and nothing says that once it has run, n and N walk the
-- matches -- which is the one piece of vim this editor genuinely needs you to
-- know, because <C-f> deliberately leaves you in Normal mode so those keys are
-- live. So it says so, in the corner, in italics, and only while it is true.
--
-- A float rather than :echo, because the cmdline is already spoken for: the
-- prompt itself is on that row while you type, and the moment you press Enter
-- nvim writes its own "/seen  [2/3]" there. Echoing would have to destroy the
-- match counter to say anything, and the counter is worth more than the hint.
--
-- It lives exactly as long as the highlight does -- same InsertEnter, same
-- moment -- so it cannot end up advertising keys that have gone back to being
-- letters. Getting that wrong would be worse than no hint at all.
-- ---------------------------------------------------------------------------
-- Reachable from quit_drill, far below: a blocking prompt must be able to get
-- the hint off the screen before it draws.
local hide_search_hint = function() end

do
  local hint_win, hint_buf = nil, nil

  -- italic, in the colourscheme's own comment colour rather than a hardcoded
  -- grey, so it stays quiet whichever scheme is swapped in at the top of the file
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "DrillSearchHint",
    { fg = comment and comment.fg or nil, italic = true })

  -- Esc reopens the search, prefilled with the term you just used, so you can
  -- edit it instead of retyping it. It is mapped ONLY while the hint is up and
  -- unmapped the moment it goes -- the pair is what keeps this honest. A
  -- permanent Normal-mode <Esc> mapping would swallow the Esc that cancels a
  -- pending count or operator, which is still plain vim here.
  local function back_to_search()
    local pat = vim.fn.getreg("/")
    -- "n": typed as-is, NOT through replace_termcodes -- a pattern containing
    -- something like <C-r> must arrive as those five characters, not as a key.
    vim.api.nvim_feedkeys("/" .. pat, "n", false)
  end

  local function esc_unbind() pcall(vim.keymap.del, "n", "<Esc>") end
  local function esc_bind()
    vim.keymap.set("n", "<Esc>", back_to_search, { silent = true })
  end

  local function hint_hide()
    if hint_win and vim.api.nvim_win_is_valid(hint_win) then
      pcall(vim.api.nvim_win_close, hint_win, true)
    end
    hint_win = nil
    esc_unbind()
  end

  local function hint_show(text)
    if vim.o.lines < 4 or vim.o.columns < 24 then return end   -- no room: say nothing
    if not (hint_buf and vim.api.nvim_buf_is_valid(hint_buf)) then
      hint_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[hint_buf].bufhidden = "hide"
    end
    local line = " " .. text .. " "
    vim.api.nvim_buf_set_lines(hint_buf, 0, -1, false, { line })
    local w = vim.fn.strdisplaywidth(line)
    -- The STATUSLINE row -- right above the prompt, which is where you are
    -- looking. Getting here took two wrong answers:
    --   * the last TEXT row (lines-3) is where nvim expands the message area
    --     for a multi-line prompt. <C-S-q> with the hint up drew the quit
    --     dialog mangled -- measured at 20 rows, the float sat at row 17 and
    --     the screen showed "n next N previou" truncated with a stale "press
    --     Enter to search" repainted across the choices.
    --   * the top row is safe but useless: the hint is about the search, and
    --     the search is at the bottom of the screen.
    -- The statusline is never expanded over by messages, and the one prompt
    -- that would fight it -- confirm(), behind <C-S-q> -- calls
    -- hide_search_hint() before it draws. The cost is the right-hand end of
    -- the ruler while a hint is up, and it comes back the moment the hint goes.
    local cfg = {
      relative = "editor",
      row = math.max(0, vim.o.lines - 2),
      col = math.max(0, vim.o.columns - w),
      width = w, height = 1,
      style = "minimal", focusable = false, zindex = 200, noautocmd = true,
    }
    if hint_win and vim.api.nvim_win_is_valid(hint_win) then
      pcall(vim.api.nvim_win_set_config, hint_win, cfg)
    else
      local ok, win = pcall(vim.api.nvim_open_win, hint_buf, false, cfg)
      if not ok then return end
      hint_win = win
      vim.wo[hint_win].winhl = "Normal:DrillSearchHint"
    end
    vim.cmd("redraw")
  end

  -- The cmdtype is checked in the CALLBACK, not with a pattern, and that is not
  -- a style choice. An autocmd pattern is matched as a FILE pattern, where "?"
  -- means "any single character" -- so pattern = { "/", "?" } fires for EVERY
  -- one-character cmdtype: ":" commands, input() prompts, and the confirm()
  -- dialog behind <C-S-q>. Measured: pressing <C-S-q> with a search hint up
  -- popped "press Enter to search" back onto the screen on top of the quit
  -- dialog, because confirm() matched "?".
  local function is_search()
    local t = vim.v.event and vim.v.event.cmdtype
    return t == "/" or t == "?"
  end

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    callback = function()
      if not is_search() then return hint_hide() end
      esc_unbind()   -- the prompt is open; Esc there cancels it, as it should
      -- the Esc tail is only true where the abort leg below can startinsert:
      -- in the listing (and the REPL's scrollback) Esc just cancels, and a
      -- hint that overpromises is worse than no hint at all
      hint_show(typing_buffer()
        and "press Enter to search     Esc  back to typing"
        or "press Enter to search")
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    callback = function()
      if not is_search() then return end
      local aborted = vim.v.event and vim.v.event.abort
      -- Esc BACKS OUT ONE LEVEL, all the way. From a finished search it
      -- reopens the prompt; from the prompt it drops the search and puts you
      -- back where you were typing. Without this last step the chain dead-ends
      -- in Normal mode with no key that returns you to insert -- which in an
      -- editor whose premise is that you never press i is the wrong place to
      -- leave someone.
      if aborted then
        vim.schedule(function()
          if typing_buffer() then
            local from = search_from
            search_from = nil
            if from then
              -- put the caret back on the Insert spot stashed by <C-f>;
              -- startinsert alone lands one column LEFT of it, because the
              -- mapping's <Esc> had already shifted the cursor. At end of
              -- line the stashed column is past the last character, where
              -- Normal mode cannot sit -- that spot needs startinsert!.
              pcall(vim.api.nvim_win_set_cursor, 0, from)
              if from[2] >= #vim.api.nvim_get_current_line() then
                vim.cmd("startinsert!")
              else
                vim.cmd("startinsert")
              end
            else
              vim.cmd("startinsert")
            end
          end
        end)
      else
        search_from = nil      -- the search ran; the stash is history
      end
      -- Deferred for the same reason the highlight clear is: the search has not
      -- actually run yet when CmdlineLeave fires, so "did it match?" cannot be
      -- answered from in here.
      vim.schedule(function()
        -- Still in Normal? Deferring the show opens a race against the hide:
        -- press i quickly enough after Enter and InsertEnter fires FIRST, hides
        -- the hint, and then this lands and puts it back -- leaving "n next
        -- N previous" on screen in insert mode, where both are just letters.
        -- Caught by the headless suite, where every key arrives in one burst
        -- and the race is the normal case rather than the rare one.
        if vim.fn.mode(1):sub(1, 1) ~= "n" then return hint_hide() end
        local pat = vim.fn.getreg("/")
        -- Nothing to walk means nothing to advertise: a cancelled search, or one
        -- whose pattern matches nothing, gets no hint rather than a wrong one.
        if aborted or pat == "" or vim.fn.search(pat, "nw") == 0 then
          return hint_hide()
        end
        esc_bind()
        hint_show("n  next     N  previous     Esc  back to search")
      end)
    end,
  })

  -- the hint and the highlight end together, on the keystroke that makes both
  -- of them false
  vim.api.nvim_create_autocmd({ "InsertEnter", "VimResized" }, { callback = hint_hide })
  hide_search_hint = hint_hide
end

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

-- The LeetCode desk: preload.py lives next to this config, and every run and
-- REPL routes through it, so Counter, deque, heappush and friends are live
-- with no import line in the file. Resolved from this file's own path because
-- the config deliberately knows nothing about DRILL_HOME; absent (an install
-- that predates the shim), runs are plain python3, exactly as before.
local preload = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/preload.py"

-- Which python3, spelled out only when the bare name would be the WRONG one.
-- WSL appends the Windows PATH, so on a box with no Linux python installed
-- `python3` resolves to the Store App Execution Alias under
-- /mnt/c/.../WindowsApps -- a zero-byte stub that opens the Microsoft Store
-- instead of running your file. It would do that inside a 15-row split, which
-- makes both Ctrl+R and Ctrl+E look broken for a reason nothing on screen
-- explains. Anything under /mnt is a Windows binary, so keep walking PATH.
-- Everywhere else this stays the literal string "python3", exactly as before.
-- exepath returns "" when there is no python3 on PATH at all, and "" matches no
-- prefix -- so a bare-name fallthrough would hand Ctrl+R and Ctrl+E a command
-- that cannot start, with none of the warning below. Absent and Store-alias are
-- the same outcome here: no usable interpreter.
local python = "python3"
local found_py = vim.fn.exepath("python3")
if found_py == "" or found_py:match("^/mnt/") then
  local found = nil
  for dir in (vim.env.PATH or ""):gmatch("[^:]+") do
    if not dir:match("^/mnt/") and vim.fn.executable(dir .. "/python3") == 1 then
      found = dir .. "/python3"
      break
    end
  end
  if found then
    python = vim.fn.shellescape(found)
  else
    -- Nothing to fall back TO. Leaving the bare name here would hand Ctrl+R and
    -- Ctrl+E the Store alias anyway, and they would open the Microsoft Store in
    -- a 15-row split with nothing on screen explaining it. install.sh refuses
    -- to proceed in this state, but nvim can be started without it, so say the
    -- true thing once rather than fail mutely at the first keypress.
    python = nil
    vim.schedule(function()
      vim.notify("drill: no usable python3 on PATH"
        .. (found_py == "" and " (none found)"
                            or " (`python3` is the Windows Store alias)")
        .. " -- Ctrl+R and Ctrl+E are disabled. "
        .. (IS_WSL and "Install a Linux python3 (apt install python3); the "
                    .. "Windows one cannot run these files."
                    or "Put a python3 on your PATH."),
        vim.log.levels.WARN)
    end)
  end
end

local function py_cmd(flags, f)
  if not python then return nil end   -- no usable interpreter; callers bail
  local cmd = python .. flags .. " "
  if vim.fn.filereadable(preload) == 1 then
    cmd = cmd .. vim.fn.shellescape(preload) .. " "
  end
  return cmd .. vim.fn.shellescape(f)
end

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
-- What <C-e> and <C-r> are about to run, and whether it has changed since the
-- interpreter last read it.
--
-- Two guards, and both were missing. `buftype ~= ""` let the directory listing
-- through, for the reason above; and expand("%:p") is the EMPTY STRING there,
-- which in Lua is truthy -- so `if not f then return end` at both call sites
-- never fired and <C-e> in the listing cheerfully opened a split running
-- `python3 -i ''`, which is a runpy traceback and then a live >>>. Measured:
-- winnr('$') == 2, bufname "term://...". An empty name has to be turned into
-- nil for a `not f` guard to mean anything.
local function source_state()
  if not typing_buffer() then return last_file, repl_tick end    -- not a file: no news
  vim.cmd("silent update")
  local f = vim.fn.expand("%:p")
  if f == "" then return nil end                                 -- nothing to run
  last_file = f
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
  local cmd = py_cmd("", f)
  if not cmd then return end                           -- the warning already said why
  vim.cmd("botright " .. RUN_H .. "split | terminal " .. cmd)
  out_win = vim.api.nvim_get_current_win()
end

-- start python on the current code, reusing the split if one is already there.
local function repl_spawn(f, tick)
  local cmd = py_cmd(" -i", f)
  if not cmd then return end                           -- the warning already said why
  local stale = repl_buf
  if shows(repl_win, stale) then
    vim.api.nvim_set_current_win(repl_win)             -- swap in place, no flicker
  else
    vim.cmd("botright " .. RUN_H .. "split")
  end
  vim.cmd("terminal " .. cmd)
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

-- ---------------------------------------------------------------------------
-- A finished run window closes itself when you leave it.
--
-- <C-r>'s output is throwaway, and while you are standing IN it any key
-- dismisses it -- that is nvim's own behaviour for a terminal whose job has
-- ended, and it is why the run loop feels like "run, read it, carry on".
--
-- But only while you are standing in it. Go back to the file first -- a click,
-- <C-w>k -- and nothing closes it, and there is no key in this config that
-- will: it sits there holding 15 rows, typing in the file does not touch it,
-- and the only way out is :q, which is the command line this editor exists to
-- avoid. Worse, <C-e> then opens the interpreter UNDER it and you are looking
-- at three windows with the file squeezed into whatever is left. Measured
-- before this: winnr('$') == 3.
--
-- So leaving it is the dismissal. The job state is what makes that safe: a
-- FINISHED program's output is just text you have read, but a program still
-- running is one you may be talking to -- <C-r> on a script that calls input()
-- puts you at its prompt -- so a live one is left exactly where it is.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("WinLeave", {
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if not (out_win and win == out_win) then return end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "terminal" then return end
    local id = vim.b[buf].terminal_job_id
    if id and vim.fn.jobwait({ id }, 0)[1] == -1 then return end   -- still running
    -- deferred: you cannot close the window you are in the middle of leaving,
    -- and by the next tick the cursor is already somewhere else.
    vim.schedule(function()
      if out_win and vim.api.nvim_win_is_valid(out_win)
         and #vim.api.nvim_list_wins() > 1 then          -- never the last window
        pcall(vim.api.nvim_win_close, out_win, true)
      end
      out_win = nil
    end)
  end,
})

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

-- ---------------------------------------------------------------------------
-- Quit  --  Ctrl+Shift+Q
--
-- Getting out was the last thing that still needed a command line: Esc, then
-- :qa!, typed in full, every time. In an editor whose whole premise is that you
-- never leave insert, the exit should not be the one place you have to.
--
-- Ctrl+Shift+Q, and it only exists for the same reason <C-S-z> does: in the
-- legacy encoding Shift is dropped from a control chord, so Ctrl+Q and
-- Ctrl+Shift+Q are both 0x11 and cannot be told apart. With CSI-u negotiated
-- they are separate keys -- measured, ESC[113;6u fires <C-S-q> while a bare
-- 0x11 still fires <C-q> -- so this costs the visual-block binding nothing.
-- Every other candidate was already spoken for: <C-q> IS visual block, <C-w> is
-- the window prefix, and <C-c>/<C-d> are deliberately left to python.
--
-- Bound in "t" as well, so you can quit from inside the interpreter without
-- pressing <C-e> to get out of it first. python has no use for <C-S-q>, and
-- <C-c>/<C-d> are untouched, so nothing is taken away from it.
--
-- :wall then :qa! -- in that order and both needed. The autosave debounce means
-- the last few characters you typed may still be pending, so write first; and
-- the ! is what lets it quit while python is still live, which is the whole
-- reason the old escape hatch was :qa! and not :wqa (:wqa REFUSES while a
-- terminal job is running).
-- ---------------------------------------------------------------------------
local function repl_running()
  if not (repl_buf and vim.api.nvim_buf_is_valid(repl_buf)) then return false end
  local ok, id = pcall(function() return vim.b[repl_buf].terminal_job_id end)
  if not ok or not id then return false end
  return vim.fn.jobwait({ id }, 0)[1] == -1        -- -1 means still running
end

local function quit_drill()
  -- Off the screen before the dialog draws. Belt and braces alongside moving
  -- the hint to the top row: a prompt is the one thing that repaints the whole
  -- bottom of the screen, and a float competing with it looks like a bug in the
  -- editor rather than in the hint.
  hide_search_hint()
  -- The prompt says what you are about to kill. Quitting with a live REPL is
  -- normal here -- <C-e> leaves python running on purpose -- so this is a
  -- reminder, not a warning, and Quit is still one keystroke away.
  local msg = repl_running()
      and "Quit drill?  (python is still running -- it will be killed)"
      or  "Quit drill?"
  -- default 2 = Cancel: a mistyped chord must never be the one that quits.
  local pick = vim.fn.confirm(msg, "&Quit\n&Cancel", 2, "Question")
  if pick ~= 1 then
    type_here()                                    -- cancelled: back to typing
    return
  end
  vim.cmd("silent! wall")                          -- flush the pending autosave
  vim.cmd("qa!")
end

map({ "n", "i", "t" }, "<C-S-q>", quit_drill, S)

-- ...and the same chord again, for terminals that cannot spell it.
--
-- Everything above assumes CSI-u. Windows Terminal 1.24 is new enough to speak
-- it and does not negotiate it with nvim, so Ctrl+Shift+Q arrives as the plain
-- legacy 0x11 -- <C-q> -- and the mapping above is simply never reached. The
-- documented way out of the editor does not exist on WSL, which leaves `:qa!`:
-- the one thing this whole section was written to stop being necessary.
--
-- So bind what actually ARRIVES. This is not a second, different key to learn:
-- on such a terminal the user presses Ctrl+Shift+Q, exactly as documented, and
-- <C-q> is what nvim is handed.
--
-- INSERT AND TERMINAL, never normal, and gated on WSL. Each of those three
-- choices costs something:
--
--   * normal mode keeps <C-q> as visual block (CONFLICT 2). It is the ONLY
--     route to a block here, since <C-v> in normal mode is paste -- so binding
--     the prompt there would leave no way to ask for one, while quitting still
--     has :qa!. From normal mode on such a terminal the chord gives you a
--     block; press i first.
--
--   * terminal mode IS included, deliberately: <C-S-q> is bound in n/i/t so
--     you can quit from inside the interpreter without pressing <C-e> first,
--     and a fallback that skipped it would take that away on the one platform
--     that needs a fallback at all. It is not a free key there either --
--     readline in emacs mode binds ^Q to quoted-insert -- but ^V is bound to
--     the same command, so quoted-insert survives. A fair trade, not a free
--     one. (drill.sh's `stty -ixon` is what frees ^Q from XON in the first
--     place.)
--
--   * in insert, vanilla <C-q> is literal-insert, the twin of <C-v>. In a
--     Python scratchpad where <C-v> is already paste that is close to
--     unreachable, and a quit prompt defaulting to Cancel is the better use of
--     the key -- but it IS a real vim behaviour, so nowhere but WSL loses it.
--
-- The gate is IS_WSL, NOT the protocol: there is no runtime signal for whether
-- CSI-u was negotiated, so a WSL session whose terminal DOES speak it gets this
-- binding too, and bare <C-q> quits from insert there as well. Off WSL --
-- macOS, and Linux desktops with or without CSI-u -- the block is skipped and
-- nothing changes.
if IS_WSL then
  map({ "i", "t" }, "<C-q>", quit_drill, S)
end
