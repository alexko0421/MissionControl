# Inline Permission Approval — Design Spec

**Date:** 2026-04-03
**Status:** Approved

## Goal

Allow users to approve/deny Claude Code tool permissions directly from MissionControl's floating window, without needing to switch to the terminal. Both terminal and MissionControl show the prompt simultaneously — either can be used.

## Approach: PreToolUse + tmux send-keys (方案 B)

Terminal displays the permission prompt as normal. MissionControl shows a permission card at the same time. User can respond from either location.

## Flow

```
Claude Code wants to use a tool
→ Terminal shows permission prompt (normal Claude Code behavior)
→ PreToolUse hook fires (fire-and-forget, non-blocking)
  → sends permission info via socket to MissionControl
  → MC displays permission card in floating window

Two response paths:
  Path A: User clicks Allow/Deny in MC
    → MC calls tmux send-keys to type response into terminal
    → Claude Code continues
    → PostToolUse hook fires → MC card auto-dismisses

  Path B: User responds directly in terminal
    → Claude Code continues
    → PostToolUse hook fires → MC card auto-dismisses
```

## Permission Card UI

- Warning icon + tool name (Bash / Edit / Write / etc.)
- Tool-specific content:
  - **Bash**: `$ command` in monospace code block + description
  - **Edit**: file path + unified diff preview (deletions in red, additions in green)
  - **Write**: file path + content preview
  - **Other tools**: tool name + input summary
- **Two buttons**: Allow / Deny

## Card Lifecycle

1. **Appear**: PreToolUse hook sends `permission_request` message via socket
2. **Respond** (Path A): User clicks button → `tmux send-keys` sends "y" or "n" to the agent's terminal pane
3. **Dismiss**: PostToolUse hook sends `question_resolved` message → card auto-disappears with animation

If user responds in terminal instead (Path B), the PostToolUse hook still fires and dismisses the card automatically.

## Hook Configuration

```json
{
  "PreToolUse": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "python3 ~/.mission-control/hooks/mc-pretool-hook.py"
    }]
  }],
  "PostToolUse": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "python3 ~/.mission-control/hooks/mc-posttool-hook.py"
    }]
  }]
}
```

## Technical Details

### mc-pretool-hook.py
- Reads tool_name, tool_input, session_id, cwd from stdin
- Detects tmux session/window/pane
- Sends `permission_request` message via mc-bridge.py (fire-and-forget, non-blocking)
- Does NOT block Claude Code — terminal prompt appears immediately

### mc-posttool-hook.py
- Sends `question_resolved` message via mc-bridge.py
- MC dismisses the permission card

### AgentStore (Swift)
- `handlePermissionRequest()`: stores permission data, displays card
- Card response calls `tmux send-keys` with "y" (Allow) or "n" (Deny)
- `onQuestionResolved`: clears pending permission, dismisses card

### PermissionCardView (Swift)
- Displays tool info and diff preview
- Two buttons: Allow (green) / Deny (dark)
- Auto-dismiss animation when resolved

## What This Is NOT

- This does NOT replace or block the terminal prompt
- This does NOT use the PermissionRequest hook type
- This does NOT require any AI processing
