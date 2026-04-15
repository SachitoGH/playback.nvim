local M     = {}
local uv    = vim.uv or vim.loop
local state = nil

local function make_timer(delay_ms, callback)
  local t = uv.new_timer()
  t:start(
    math.max(0, math.floor(delay_ms)),
    0,
    vim.schedule_wrap(function()
      if not t:is_closing() then
        t:stop()
        t:close()
      end
      callback()
    end)
  )
  return t
end

local function cancel_timer(t)
  if t then
    pcall(function()
      if not t:is_closing() then
        t:stop()
        t:close()
      end
    end)
  end
end

function M.play(session)
  if state then M.stop() end

  local cfg   = require("playback").config
  local speed = cfg.default_speed

  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)

  local fname = vim.fn.fnamemodify(session.file, ":t")
  vim.api.nvim_set_option_value("buftype",    "nofile", { buf = buf })
  vim.api.nvim_set_option_value("swapfile",   false,    { buf = buf })
  vim.api.nvim_set_option_value("bufhidden",  "wipe",   { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true,     { buf = buf })
  local ft = vim.filetype.match({ filename = session.file })
  if ft then vim.api.nvim_set_option_value("filetype", ft, { buf = buf }) end
  pcall(vim.api.nvim_buf_set_name, buf, "playback://" .. fname)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, session.snapshot)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  state = {
    buf     = buf,
    win     = win,
    session = session,
    index   = 1,
    speed   = speed,
    paused  = false,
    timer   = nil,
  }

  local ko = { noremap = true, silent = true, buffer = buf, nowait = true }
  vim.keymap.set("n", "<Space>", M.toggle_pause, ko)
  vim.keymap.set("n", "<Esc>",   M.stop, ko)
  vim.keymap.set("n", "q",       M.stop, ko)
  vim.keymap.set("n", "=", function() M.adjust_speed(1.5)     end, ko)
  vim.keymap.set("n", "-", function() M.adjust_speed(1 / 1.5) end, ko)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = buf,
    once     = true,
    callback = function()
      if state and state.buf == buf then
        cancel_timer(state.timer)
        state = nil
      end
    end,
  })

  M._update_hud()
  M._tick()
end

function M.stop()
  if not state then return end
  cancel_timer(state.timer)
  local s = state
  state = nil
  -- nil state before closing so BufWipeout autocmd is a no-op
  pcall(vim.api.nvim_win_close, s.win, true)
end

function M.toggle_pause()
  if not state then return end
  state.paused = not state.paused
  if state.paused then
    cancel_timer(state.timer)
    state.timer = nil
  else
    M._tick()
  end
  M._update_hud()
end

function M.adjust_speed(factor)
  if not state then return end
  state.speed = math.max(0.25, math.min(8.0, state.speed * factor))
  cancel_timer(state.timer)
  state.timer = nil
  if not state.paused then M._tick() end
  M._update_hud()
end

function M._tick()
  if not state or state.paused then return end

  local events = state.session.events
  if state.index > #events then
    M._update_hud(true)
    return
  end

  local cfg    = require("playback").config
  local event  = events[state.index]
  local prev_t = state.index > 1 and events[state.index - 1].t or 0
  local delay  = math.min(event.t - prev_t, cfg.skip_idle_threshold * 1000) / state.speed

  state.timer = make_timer(delay, function()
    if not state then return end
    M._apply(event)
    state.index = state.index + 1
    M._update_hud()
    M._tick()
  end)
end

function M._apply(event)
  if not state then return end
  if not vim.api.nvim_buf_is_valid(state.buf) then
    M.stop(); return
  end

  local ok = pcall(function()
    vim.api.nvim_set_option_value("modifiable", true,  { buf = state.buf })
    vim.api.nvim_buf_set_lines(state.buf, event.first, event.last, false, event.lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

    if vim.api.nvim_win_is_valid(state.win) then
      local line_count = vim.api.nvim_buf_line_count(state.buf)
      local cur = event.new_last > event.first and event.new_last or event.first + 1
      vim.api.nvim_win_set_cursor(state.win, { math.max(1, math.min(cur, line_count)), 0 })
    end
  end)

  if not ok then M.stop() end
end

function M._update_hud(done)
  if not state then return end
  if not vim.api.nvim_win_is_valid(state.win) then return end

  local total   = math.max(1, #state.session.events)
  local pct     = math.floor((state.index - 1) / total * 100)
  local spd_str = state.speed ~= 1.0 and string.format("  %.1fx", state.speed) or ""

  local line
  if done then
    line = "  playback · done" .. spd_str .. "  [q/esc] close"
  elseif state.paused then
    line = string.format("  playback · PAUSED %d%%%s  [space] resume  [esc] stop  [=/-] speed", pct, spd_str)
  else
    line = string.format("  playback · %d%%%s  [space] pause  [esc] stop  [=/-] speed", pct, spd_str)
  end

  -- winbar format shares statusline syntax: %% renders as literal %
  vim.wo[state.win].winbar = line:gsub("%%", "%%%%")
  vim.cmd("redraw!")
end

return M
