# MissionControl Tmux Integration Design

## Problem

MissionControl has two independent question sources that conflict:

1. **Hook-based**: `mc-pretool-hook.py` fires on every tool call, sending questions to MissionControl via socket. These are real approval requests.
2. **Polling-based**: Every 3 seconds, `TMuxBridge.detectPrompt()` scans the last 30 lines of tmux output and guesses whether a prompt exists using regex. This produces false positives — terminal output gets misidentified as options, questions appear that the user never saw, and stale prompts linger.

The result: fake options, duplicate questions, and an unreliable experience.

Additionally, the non-tmux AppleScript keystroke injection fails due to macOS accessibility restrictions, making MissionControl unable to type answers into Terminal.app.

## Solution

**Hook is the single source of truth for questions. Tmux send-keys is the response channel.**

### Design Principles

- Only hook-delivered questions are real. No guessing from terminal output.
- Hook fires and returns immediately (fire-and-forget) so Claude Code shows its own prompt.
- MissionControl uses `tmux send-keys` to type answers — no AppleScript permissions needed.
- Both terminal and MissionControl show the question. User clicks whichever is convenient.

## Changes

### 1. mc-pretool-hook.py: Detect tmux and send session info

Check `$TMUX` environment variable. If present, extract session, window, and pane from tmux commands and include them in the question message.

```python
import shutil

def get_tmux_info():
    """Return (session, window, pane) if running inside tmux, else (None, None, None)."""
    if not os.environ.get("TMUX"):
        return None, None, None
    tmux = shutil.which("tmux") or "/opt/homebrew/bin/tmux"
    try:
        result = subprocess.run(
            [tmux, "display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"],
            capture_output=True, text=True, timeout=5
        )
        parts = result.stdout.strip().replace(":", " ").replace(".", " ").split()
        if len(parts) == 3:
            return parts[0], int(parts[1]), int(parts[2])
    except Exception:
        pass
    return None, None, None
```

Add tmux fields to the bridge call:
```python
session, window, pane = get_tmux_info()
if session is not None:
    cmd += ["--tmux-session", session, "--tmux-window", str(window), "--tmux-pane", str(pane)]
```

### 2. mc-bridge.py: cmd_question accepts tmux args, stays fire-and-forget

Add `--tmux-session`, `--tmux-window`, `--tmux-pane` optional args to the question subparser. Include them in the socket message if present. Keep `wait_for_response=False`.

### 3. MCSocketServer / AgentStore: Store tmux info from question messages

When handling a `question` message that includes `tmux_session`, `tmux_window`, `tmux_pane`, update the agent's tmux fields so `tmuxTarget` is set. This way `respondQuestion` will use the tmux path.

### 4. AgentStore: Disable prompt detection from polling

In `pollTerminals()`, remove or skip the call to `TMuxBridge.detectPrompt()`. Polling should only update `terminalLines` for display, not create questions. This eliminates all false-positive prompts.

### 5. Add PostToolUse hook to clear stale questions

Create `mc-posttool-hook.py` that fires after a tool completes. It sends a `question_resolved` message to MissionControl, which clears `pendingQuestion` for the agent. This handles the case where the user answers in terminal (not MissionControl) — the question card disappears.

Register this hook in Claude Code settings alongside the existing PreToolUse hook.

### 6. sendKey values

The hook options use sendKeys that match Claude Code's terminal prompt:
- Yes → `"y"`
- Yes, don't ask again → `"!"`  
- No → `"n"`

These are already set correctly in the current code.

## Flow

```
Claude Code tool call
  -> PreToolUse hook fires
  -> Hook detects tmux: session=main, window=0, pane=0
  -> Hook sends question + tmux info to MissionControl (fire-and-forget)
  -> Hook returns immediately (no stdout output)
  -> Claude Code shows permission prompt in terminal

Meanwhile:
  -> MissionControl receives question via socket
  -> Stores tmux info with agent
  -> Shows question card in Ask tab

User chooses one:
  Option A: Types "y" in terminal directly -> done
  Option B: Clicks Yes in MissionControl
    -> respondQuestion() sees tmuxTarget is set
    -> tmux send-keys -t main:0.0 "y" Enter
    -> Terminal receives keystroke -> done

After tool completes:
  -> PostToolUse hook fires
  -> Sends question_resolved to MissionControl
  -> MissionControl clears pendingQuestion
```

## Files to modify

| File | Change |
|------|--------|
| `cli/hooks/mc-pretool-hook.py` | Add tmux detection, include tmux args in bridge call |
| `cli/hooks/mc-bridge.py` | Add tmux args to question subparser, include in message |
| `cli/hooks/mc-posttool-hook.py` | New file: PostToolUse hook to clear resolved questions |
| `MissionControl/AgentStore.swift` | Store tmux info from question messages, disable prompt detection in polling |
| `MissionControl/SocketMessage.swift` | Ensure question messages can carry tmux fields (already supported) |
| `~/.claude/settings.json` | Register PostToolUse hook |

## Out of scope

- Non-tmux support (AppleScript) — defer until macOS accessibility situation improves
- Permission request flow — keep existing blocking approach (already works)
- Plan review flow — keep existing blocking approach (already works)
