-- storage.lua
-- Persists sessions as JSON files under ~/.local/share/nvim/playback/
-- Directory per file, named by a simple hash + filename for readability.

local M  = {}
local uv = vim.uv or vim.loop

-- Map a filepath to a unique, filesystem-safe directory name
local function session_dir(filepath)
  local base = vim.fn.stdpath("data") .. "/playback"

  -- djb2-style hash of the full path for uniqueness
  local h = 5381
  for i = 1, #filepath do
    h = ((h * 33) + string.byte(filepath, i)) % 0x100000000
  end

  -- Append a short human-readable suffix from the filename
  local fname = (filepath:match("([^/\\]+)$") or "unknown")
    :gsub("[^%w%-_%.]", "_")
    :sub(1, 30)

  return string.format("%s/%08x_%s", base, h, fname)
end

function M.save(session)
  local dir = session_dir(session.file)
  vim.fn.mkdir(dir, "p")

  local path     = dir .. "/" .. math.floor(uv.hrtime() / 1e6) .. ".json"
  local ok, data = pcall(vim.json.encode, session)

  if not ok then
    vim.notify("playback: could not encode session - " .. tostring(data), vim.log.levels.ERROR)
    return
  end

  local f = io.open(path, "w")
  if f then
    f:write(data)
    f:close()
    M._prune(session.file)
  else
    vim.notify("playback: could not write session to " .. path, vim.log.levels.ERROR)
  end
end

function M.list(filepath)
  local dir   = session_dir(filepath)
  if vim.fn.isdirectory(dir) == 0 then return {} end

  local files    = vim.fn.glob(dir .. "/*.json", false, true)
  local sessions = {}

  for _, path in ipairs(files) do
    local f = io.open(path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == "table" then
        data._path = path  -- internal, for deletion
        table.insert(sessions, data)
      end
    end
  end

  -- Most recent first
  table.sort(sessions, function(a, b)
    return (a.started_at or 0) > (b.started_at or 0)
  end)

  return sessions
end

function M.delete(session)
  if session._path then
    os.remove(session._path)
  end
end

function M._prune(filepath)
  local cfg      = require("playback").config
  local sessions = M.list(filepath)
  for i = cfg.max_sessions + 1, #sessions do
    M.delete(sessions[i])
  end
end

return M
