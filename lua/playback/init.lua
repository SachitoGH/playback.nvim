-- playback.nvim
-- Record your editing sessions silently. Replay them as a ghost.

local M = {}

M.config = {
  auto_record         = true,  -- start recording automatically on file open
  max_sessions        = 10,    -- max saved sessions per file (oldest pruned)
  min_duration_secs   = 30,    -- discard sessions shorter than this
  skip_idle_threshold = 3,     -- compress pauses longer than N seconds
  default_speed       = 1.0,   -- replay speed multiplier
  keymap              = nil,   -- e.g. "<leader>se" to open the picker
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("Playback", function()
    M.open()
  end, { desc = "Open playback session picker", force = true })

  if M.config.keymap then
    vim.keymap.set("n", M.config.keymap, M.open, { desc = "Open playback session picker" })
  end

  if not M.config.auto_record then return end

  local recorder = require("playback.recorder")
  local group = vim.api.nvim_create_augroup("Playback", { clear = true })

  -- Attach to already-open buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      recorder.start(buf)
    end
  end

  -- Attach to new buffers as they're read/created
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(ev)
      recorder.start(ev.buf)
    end,
  })

  -- Save when a buffer is unloaded
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(ev)
      recorder.stop(ev.buf)
    end,
  })

  -- Safety net: save everything on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        recorder.stop(buf)
      end
    end,
  })
end

-- Open the session picker for the current buffer's file
function M.open()
  local buf  = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)

  if path == "" then
    vim.notify("playback: current buffer has no file path", vim.log.levels.WARN)
    return
  end

  local sessions = require("playback.storage").list(path)

  require("playback.ui").open_picker(sessions, path, function(session)
    require("playback.player").play(session)
  end)
end

return M
