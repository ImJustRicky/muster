# Log Viewer (Ctrl+O) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a full-screen scrollable log viewer to muster's streambox, toggled with Ctrl+O during and after deploys.

**Architecture:** Extend `stream_in_box()` in `lib/tui/streambox.sh` with an expanded mode. Replace `sleep 0.3` with `read -rsn1 -t 0.3` for non-blocking key detection. Add a new `_log_viewer()` function for the full-screen view with scroll support. Log coloring via pattern matching, configurable in global settings.

**Tech Stack:** Bash 3.2+, tput, read -rsn1

---

### Design

#### Modes

- **Collapsed** (existing): 4-line bordered box showing last 4 log lines
- **Expanded** (new): Full-screen log viewer with header, scrollable content, footer

Toggle: Ctrl+O (`\x0f`) switches between modes. Works during live deploy and after completion.

#### Expanded Layout

```
 // muster  Website deploy log                    Ctrl+O close
────────────────────────────────────────────────────────────────
 Step 1/5 : FROM node:18-alpine
  ---> abc123def
 Step 2/5 : WORKDIR /app
  ---> Using cache
 Step 3/5 : COPY package*.json ./
 npm install...
 added 1423 packages in 12s
 Step 4/5 : COPY . .
 Step 5/5 : RUN npm run build
 Building Next.js app...
 Successfully built 9f44b69329e5
 Starting container on port 3000...

────────────────────────────────────────────────────────────────
 ↑↓/jk scroll  •  following                       Ctrl+O close
```

- **Header**: Yellow/mustard background, `// muster` logo, service title, close hint
- **Content**: `TERM_ROWS - 3` visible lines (header + separator + footer)
- **Footer**: Scroll hints, mode indicator ("following" or "line N/M")

#### Scrolling

- `↑` / `k`: Scroll up one line (exits auto-follow)
- `↓` / `j`: Scroll down one line
- `G`: Jump to bottom (re-enables auto-follow)
- `g`: Jump to top
- Auto-follow: when at bottom, new lines scroll in automatically
- Scrolling up pauses auto-follow, footer shows position

#### Log Color Coding

Pattern-matched per line (applied in expanded view):

| Pattern | Color |
|---------|-------|
| `error`, `Error`, `ERROR`, `fatal`, `FATAL` | Red |
| `warn`, `Warning`, `WARNING` | Yellow |
| `success`, `Successfully`, `built`, `healthy` | Green |
| `Step`, `-->`, `--->` | Accent (mustard) |
| Everything else | Default/dim |

#### Global Setting: `log_color_mode`

| Value | Behavior |
|-------|----------|
| `auto` (default) | Pattern-based coloring |
| `raw` | Preserve original ANSI from command output |
| `none` | Plain text, no colors |

Configurable via `muster settings` TUI or `muster settings --global log_color_mode raw`.

#### After-Deploy Hint

After `stream_in_box` completes (command finished), show a brief hint:
```
  Ctrl+O to view full log
```
Listen for Ctrl+O for 2 seconds. If pressed, open expanded view with the completed log (read-only, no auto-follow). If not pressed, continue to health check.

---

### Files to Modify

| File | Change |
|------|--------|
| `lib/tui/streambox.sh` | Replace sleep with read -rsn1, add expanded mode toggle, add `_log_viewer()` |
| `lib/core/config.sh` | Add `log_color_mode` to default global settings |
| `lib/commands/settings.sh` | Add `log_color_mode` to settings TUI + CLI validation |

### Bash 3.2 Constraints

- `read -rsn1 -t 0.3` works on macOS bash 3.2 (no fractional for `-t` on `read` with multi-char — but `-t 1` with `-sn1` works; use 1-second timeout)
- No associative arrays for color rules — use case statements
- `tput cup` for cursor positioning, `tput ed` for clearing below
- `tput smcup` / `tput rmcup` for alternate screen buffer (clean enter/exit)

---

### Task 1: Add key detection to streambox refresh loop

**Files:**
- Modify: `lib/tui/streambox.sh:47-78` (the while loop)

Replace `sleep 0.3` with `read -rsn1 -t 1` to detect Ctrl+O. When detected, set a flag and call the log viewer. When viewer returns (Ctrl+O pressed again), resume collapsed mode.

### Task 2: Implement `_log_viewer()` function

**Files:**
- Create/modify: `lib/tui/streambox.sh`

The full-screen viewer:
1. Enter alternate screen (`tput smcup`)
2. Draw header bar (yellow bg, `// muster`, title, close hint)
3. Read full log file into line array
4. Render visible window based on scroll offset
5. Key loop: `read -rsn1 -t 1` for arrows/j/k/g/G/Ctrl+O
6. On Ctrl+O or command completion: exit alternate screen (`tput rmcup`)

Handle arrow keys (escape sequences: `\x1b[A` for up, `\x1b[B` for down) by reading additional chars after `\x1b`.

### Task 3: Add log line coloring

**Files:**
- Modify: `lib/tui/streambox.sh`

Add `_colorize_log_line()` function that applies pattern matching. Read `log_color_mode` from global settings. Apply in both collapsed and expanded views.

### Task 4: Add `log_color_mode` to settings

**Files:**
- Modify: `lib/core/config.sh` (default settings)
- Modify: `lib/commands/settings.sh` (TUI + CLI)

Add `log_color_mode` with values `auto`/`raw`/`none`, default `auto`.

### Task 5: Add after-deploy hint + viewer

**Files:**
- Modify: `lib/commands/deploy.sh`

After deploy completes (success path), show `Ctrl+O to view full log` hint and listen for Ctrl+O for 2 seconds. If pressed, open `_log_viewer` with the completed log file.
