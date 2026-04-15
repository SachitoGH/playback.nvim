# playback.nvim

Silently records your editing sessions and lets you replay them as a ghost in a split.

When you open a file, playback attaches to the buffer and captures every change alongside a millisecond timestamp. When the buffer is unloaded, the session is saved to disk. Later, you can open the picker, pick a session, and watch your past edits play back in real time -- pausing, scrubbing speed, or stopping at any point.

## Requirements

- Neovim 0.9+
- No external dependencies

## Installation

Using vim.pack (Neovim 0.11+):

```lua
vim.pack.add("SachitoGH/playback.nvim")
```

Using lazy.nvim:

```lua
{ "SachitoGH/playback.nvim" }
```

Then call setup somewhere in your config:

```lua
require("playback").setup()
```

## Usage

Open the session picker for the current file:

```
:Playback
```

The picker lists all saved sessions for the file, showing their age, duration, and number of recorded edits.

**Picker keys**

| Key | Action |
|-----|--------|
| `j` / `k` | move between sessions |
| `Enter` | replay the selected session |
| `d` | delete the selected session |
| `q` / `Esc` | close |

**During replay**

Playback opens a vertical split with a scratch buffer. The original file is not touched.

| Key | Action |
|-----|--------|
| `Space` | pause / resume |
| `=` | increase speed (x1.5) |
| `-` | decrease speed (x0.66) |
| `q` / `Esc` | stop and close |

Speed can be adjusted between 0.25x and 8x. The status line shows the current progress, speed, and available keys.

## How it works

On `BufReadPost` and `BufNewFile`, playback calls `nvim_buf_attach` to receive line-level change notifications. Each change is stored as a delta: the changed line range and the new content, with a millisecond offset from session start. A full snapshot of the buffer at attach time is also saved so replay can start from the correct baseline.

Sessions are saved as JSON files under `~/.local/share/nvim/playback/`, in a per-file subdirectory named after a hash of the file path. When the buffer is unloaded or Neovim exits, the session is written to disk if it passes the minimum duration check.

During replay, long idle gaps (pauses between keystrokes) are compressed to a configurable threshold so replays stay watchable.

## Configuration

All options and their defaults:

```lua
require("playback").setup({
  auto_record         = true,  -- attach to buffers automatically on open
  max_sessions        = 10,    -- sessions to keep per file (oldest are pruned)
  min_duration_secs   = 30,    -- sessions shorter than this are discarded
  skip_idle_threshold = 3,     -- compress pauses longer than N seconds
  default_speed       = 1.0,   -- playback speed multiplier
  keymap              = nil,   -- e.g. "<leader>se" to open the picker
})
```

Setting `auto_record = false` disables automatic attachment. In that case no sessions will be recorded unless you wire up the recorder manually.

## Storage

Sessions live at:

```
~/.local/share/nvim/playback/<hash>_<filename>/<timestamp>.json
```

Each file stores the initial snapshot, the list of delta events, the session start time, and the total duration. Old sessions beyond `max_sessions` are pruned automatically when a new one is saved.
