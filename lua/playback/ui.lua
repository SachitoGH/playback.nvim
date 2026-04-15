-- ui.lua
-- Floating picker for browsing and launching past sessions.

local M = {}

-- Picker

function M.open_picker(sessions, filepath, on_select)
  if #sessions == 0 then
    vim.notify("playback: no recordings found for this file", vim.log.levels.INFO)
    return
  end

  -- Build buffer lines
  local lines = {}

  for i, s in ipairs(sessions) do
    lines[#lines + 1] = string.format(
      "  %d.  %-15s  · %-12s  · %d edits",
      i,
      M._fmt_age(s.started_at),
      M._fmt_dur(s.duration),
      s.events and #s.events or 0
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "  [enter] replay   [d] delete   [q / esc] close"

  -- Window dimensions: wide enough for the longest line, at least the hint line
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = width + 2  -- small side padding
  local height = #lines
  local row    = math.max(0, math.floor((vim.o.lines   - height) / 2) - 2)
  local col    = math.max(0, math.floor((vim.o.columns - width)  / 2))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true,    { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false,   { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = " playback ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("cursorline", true,  { win = win })
  vim.api.nvim_set_option_value("wrap",       false, { win = win })

  -- Start on first session
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  -- Helpers

  local function get_idx()
    if not vim.api.nvim_win_is_valid(win) then return nil end
    local ln  = vim.api.nvim_win_get_cursor(win)[1]
    local idx = ln
    if idx >= 1 and idx <= #sessions then return idx end
    return nil
  end

  local function close()
    pcall(vim.api.nvim_win_close, win, true)
  end

  local function redraw(updated_sessions)
    close()
    vim.schedule(function()
      M.open_picker(updated_sessions, filepath, on_select)
    end)
  end

  -- Keymaps

  local ko = { noremap = true, silent = true, buffer = buf, nowait = true }

  vim.keymap.set("n", "q",     close, ko)
  vim.keymap.set("n", "<Esc>", close, ko)

  vim.keymap.set("n", "j", function()
    local idx = get_idx()
    if idx and idx < #sessions then
      vim.api.nvim_win_set_cursor(win, { idx + 1, 0 })
    end
  end, ko)

  vim.keymap.set("n", "k", function()
    local idx = get_idx()
    if idx and idx > 1 then
      vim.api.nvim_win_set_cursor(win, { idx - 1, 0 })
    end
  end, ko)

  vim.keymap.set("n", "<CR>", function()
    local idx = get_idx()
    if not idx then return end
    local chosen = sessions[idx]
    close()
    vim.schedule(function()
      on_select(chosen)
    end)
  end, ko)

  vim.keymap.set("n", "d", function()
    local idx = get_idx()
    if not idx then return end
    require("playback.storage").delete(sessions[idx])
    table.remove(sessions, idx)
    redraw(sessions)
  end, ko)
end

-- Formatting helpers

function M._fmt_age(unix_ts)
  local diff = os.time() - (unix_ts or 0)
  if diff < 60           then return "just now"
  elseif diff < 3600     then return math.floor(diff / 60)    .. "m ago"
  elseif diff < 86400    then return math.floor(diff / 3600)  .. "h ago"
  elseif diff < 86400*2  then return "yesterday"
  elseif diff < 86400*7  then return math.floor(diff / 86400) .. " days ago"
  else return os.date("%Y-%m-%d", unix_ts) end
end

function M._fmt_dur(secs)
  secs = secs or 0
  if secs < 60 then
    return secs .. "s"
  elseif secs < 3600 then
    return math.floor(secs / 60) .. "m " .. string.format("%02ds", secs % 60)
  else
    return math.floor(secs / 3600) .. "h "
        .. string.format("%02dm", math.floor((secs % 3600) / 60))
  end
end

return M
