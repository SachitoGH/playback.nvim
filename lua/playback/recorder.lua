-- recorder.lua
-- Silently attaches to file buffers and records every change with timestamps.
-- Each recording = a full snapshot at attach time + a stream of delta events.

local M   = {}
local uv  = vim.uv or vim.loop
local active = {}  -- [bufnr] -> recording state

function M.start(bufnr)
  if active[bufnr] then return end
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  -- Only record normal file buffers
  local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
  if not ok or buftype ~= "" then return end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then return end
  if name:match("^playback://") then return end

  local snapshot   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local started_ms = uv.hrtime() / 1e6  -- milliseconds (monotonic)
  local started_at = os.time()           -- unix timestamp for display

  active[bufnr] = {
    file       = name,
    snapshot   = snapshot,
    started_ms = started_ms,
    started_at = started_at,
    events     = {},
  }

  local attached = vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, _, firstline, lastline, new_lastline)
      local rec = active[buf]
      -- Return true to detach if we stopped recording this buffer
      if not rec then return true end

      local t     = math.floor(uv.hrtime() / 1e6 - rec.started_ms)
      local lines = vim.api.nvim_buf_get_lines(buf, firstline, new_lastline, false)

      table.insert(rec.events, {
        t        = t,           -- ms since session start
        first    = firstline,   -- 0-indexed, start of changed region
        last     = lastline,    -- 0-indexed exclusive, OLD end
        new_last = new_lastline, -- 0-indexed exclusive, NEW end
        lines    = lines,       -- new content from firstline..new_lastline-1
      })
    end,
  })

  if not attached then active[bufnr] = nil end
end

function M.stop(bufnr)
  local rec = active[bufnr]
  if not rec then return end
  active[bufnr] = nil

  if #rec.events == 0 then return end

  local cfg          = require("playback").config
  local duration_ms  = uv.hrtime() / 1e6 - rec.started_ms
  local duration_sec = duration_ms / 1000

  if duration_sec < cfg.min_duration_secs then return end

  require("playback.storage").save({
    file       = rec.file,
    started_at = rec.started_at,
    duration   = math.floor(duration_sec),
    snapshot   = rec.snapshot,
    events     = rec.events,
  })
end

return M
