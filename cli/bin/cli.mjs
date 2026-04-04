#!/usr/bin/env node

import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const HOOKS_SRC = join(__dirname, '..', 'hooks');
const MC_DIR = join(homedir(), '.mission-control');
const BRIDGE_CMD = `${join(MC_DIR, 'bin', 'mc-bridge')}`;
const HOOKS_DEST = join(MC_DIR, 'hooks');
const CLAUDE_SETTINGS = join(homedir(), '.claude', 'settings.json');
const APP_PATH = '/Applications/MissionControl.app';
const DOWNLOAD_URL = 'https://github.com/alexko0421/MissionControl/releases/latest/download/MissionControl.zip';

const HOOK_FILES = [
  'mc-bridge.py',
  'mc-claude-hook.py',
  'mc-permission-hook.py',
  'mc-prompt-hook.py',
  'mc-posttool-hook.py',
];

const LEGACY_HOOK_FILES = [
  'mc-pretool-hook.py',
];

const HOOK_CONFIG = {
  hooks: {
    SessionStart: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SessionStart` }],
      },
    ],
    SessionEnd: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SessionEnd` }],
      },
    ],
    UserPromptSubmit: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event UserPromptSubmit` }],
      },
    ],
    PreToolUse: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PreToolUse` }],
      },
    ],
    PostToolUse: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PostToolUse` }],
      },
    ],
    Notification: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event Notification` }],
      },
    ],
    Stop: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event Stop` }],
      },
    ],
    SubagentStart: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SubagentStart` }],
      },
    ],
    SubagentStop: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SubagentStop` }],
      },
    ],
    PreCompact: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PreCompact` }],
      },
    ],
    PermissionRequest: [
      {
        matcher: '*',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PermissionRequest`, timeout: 86400 }],
      },
    ],
  },
};

function missionControlHookPaths() {
  return [...HOOK_FILES, ...LEGACY_HOOK_FILES].map((file) => join(HOOKS_DEST, file));
}

function isManagedMissionControlCommand(command) {
  if (!command) return false;
  return missionControlHookPaths().some((hookPath) => command.includes(hookPath))
    || command.includes('mc-bridge')
    || command.includes('mission-control');
}

const CODEX_CONFIG = join(homedir(), '.codex');
const GEMINI_CONFIG = join(homedir(), '.gemini', 'settings.json');
const CURSOR_CONFIG = join(homedir(), '.cursor', 'hooks.json');

const AGENTS = {
  'claude-code': {
    name: 'Claude Code',
    detect: () => existsSync(join(homedir(), '.claude')),
    setup: setupClaudeCode,
  },
  'codex': {
    name: 'Codex',
    detect: () => existsSync(CODEX_CONFIG),
    setup: setupCodex,
  },
  'gemini-cli': {
    name: 'Gemini CLI',
    detect: () => existsSync(join(homedir(), '.gemini')),
    setup: setupGeminiCLI,
  },
  'cursor': {
    name: 'Cursor',
    detect: () => existsSync(join(homedir(), '.cursor')),
    setup: setupCursor,
  },
};

function printHelp() {
  console.log(`
  Mission Control — monitor AI coding sessions in real time

  Usage:
    npx mission-control-ai setup               Auto-detect and install hooks for all agents
    npx mission-control-ai setup claude-code    Install hooks for Claude Code only
    npx mission-control-ai setup codex          Install hooks for Codex only
    npx mission-control-ai setup gemini-cli     Install hooks for Gemini CLI only
    npx mission-control-ai setup cursor         Install hooks for Cursor only
    npx mission-control-ai uninstall            Remove app + hooks
    npx mission-control-ai status               Show current session status
    npx mission-control-ai help                 Show this help

  Supported agents: Claude Code, Codex, Gemini CLI, Cursor
  `);
}

function installApp() {
  if (existsSync(APP_PATH)) {
    console.log('  ✓ Mission Control app already installed');
    return true;
  }

  console.log('  ↓ Downloading Mission Control app...');
  try {
    const tmpZip = '/tmp/MissionControl.zip';
    execSync(`curl -sL "${DOWNLOAD_URL}" -o "${tmpZip}"`, { stdio: 'pipe' });
    execSync(`unzip -oq "${tmpZip}" -d /Applications/`, { stdio: 'pipe' });
    execSync(`rm "${tmpZip}"`, { stdio: 'pipe' });
    // Remove quarantine so it opens without Gatekeeper warning
    execSync(`xattr -dr com.apple.quarantine "${APP_PATH}" 2>/dev/null || true`, { stdio: 'pipe' });
    console.log('  ✓ Installed Mission Control to /Applications/');
    return true;
  } catch (e) {
    console.log('  ✗ Failed to download app. You can download manually from:');
    console.log('    https://github.com/alexko0421/MissionControl/releases');
    return false;
  }
}

function setupClaudeCode() {
  let settings = {};
  if (existsSync(CLAUDE_SETTINGS)) {
    try {
      settings = JSON.parse(readFileSync(CLAUDE_SETTINGS, 'utf-8'));
    } catch {
      console.log('  ⚠ Could not parse existing settings.json — creating new one');
    }
  }
  if (!settings.hooks) settings.hooks = {};

  for (const [hookName, entries] of Object.entries(settings.hooks)) {
    const cleaned = (entries || [])
      .map((entry) => ({
        ...entry,
        hooks: (entry.hooks || []).filter((hook) => !isManagedMissionControlCommand(hook.command)),
      }))
      .filter((entry) => entry.hooks.length > 0);

    if (cleaned.length > 0) {
      settings.hooks[hookName] = cleaned;
    } else {
      delete settings.hooks[hookName];
    }
  }

  for (const [hookName, hookEntries] of Object.entries(HOOK_CONFIG.hooks)) {
    if (!settings.hooks[hookName]) {
      settings.hooks[hookName] = hookEntries;
    } else {
      const existing = settings.hooks[hookName];
      for (const entry of hookEntries) {
        const cmd = entry.hooks[0].command;
        const alreadyExists = existing.some((e) =>
          e.hooks?.some((h) => h.command === cmd)
        );
        if (!alreadyExists) {
          existing.push(entry);
        }
      }
    }
  }
  // Install statusLine for rate limit tracking
  if (!settings.statusLine) {
    settings.statusLine = `${join(MC_DIR, 'bin', 'mc-statusline')}`;
  }
  writeFileSync(CLAUDE_SETTINGS, JSON.stringify(settings, null, 2) + '\n');
  console.log('  ✓ Configured Claude Code hooks + statusLine');
}

function setupCodex() {
  const hooksFile = join(CODEX_CONFIG, 'hooks.json');
  let hooks = {};
  if (existsSync(hooksFile)) {
    try { hooks = JSON.parse(readFileSync(hooksFile, 'utf-8')); } catch {}
  }
  const bridgePath = join(HOOKS_DEST, 'mc-bridge.py');
  if (!hooks.hooks) hooks.hooks = {};
  const codexHooks = {
    'on_agent_stop': `python3 ${bridgePath} status --agent-id $AGENT_ID --status done`,
    'on_agent_start': `python3 ${bridgePath} status --agent-id $AGENT_ID --status running`,
  };
  for (const [event, cmd] of Object.entries(codexHooks)) {
    if (!hooks.hooks[event]) {
      hooks.hooks[event] = [{ type: 'command', command: cmd }];
    }
  }
  mkdirSync(CODEX_CONFIG, { recursive: true });
  writeFileSync(hooksFile, JSON.stringify(hooks, null, 2) + '\n');
  console.log('  ✓ Configured Codex hooks');
}

function setupGeminiCLI() {
  const geminiDir = join(homedir(), '.gemini');
  mkdirSync(geminiDir, { recursive: true });
  let settings = {};
  if (existsSync(GEMINI_CONFIG)) {
    try { settings = JSON.parse(readFileSync(GEMINI_CONFIG, 'utf-8')); } catch {}
  }
  const bridgePath = join(HOOKS_DEST, 'mc-bridge.py');
  if (!settings.hooks) settings.hooks = {};
  settings.hooks['mission_control_bridge'] = `python3 ${bridgePath}`;
  writeFileSync(GEMINI_CONFIG, JSON.stringify(settings, null, 2) + '\n');
  console.log('  ✓ Configured Gemini CLI hooks');
}

function setupCursor() {
  const cursorDir = join(homedir(), '.cursor');
  mkdirSync(cursorDir, { recursive: true });
  let hooks = {};
  if (existsSync(CURSOR_CONFIG)) {
    try { hooks = JSON.parse(readFileSync(CURSOR_CONFIG, 'utf-8')); } catch {}
  }
  const bridgePath = join(HOOKS_DEST, 'mc-bridge.py');
  if (!hooks.hooks) hooks.hooks = {};
  hooks.hooks['mission_control'] = { type: 'command', command: `python3 ${bridgePath}` };
  writeFileSync(CURSOR_CONFIG, JSON.stringify(hooks, null, 2) + '\n');
  console.log('  ✓ Configured Cursor hooks');
}

function setup() {
  const targetAgent = process.argv[3];
  console.log('\n  🚀 Mission Control — Setup\n');

  const appInstalled = installApp();

  mkdirSync(HOOKS_DEST, { recursive: true });
  mkdirSync(dirname(CLAUDE_SETTINGS), { recursive: true });
  console.log('  ✓ Created ~/.mission-control/hooks/');

  for (const file of HOOK_FILES) {
    const src = join(HOOKS_SRC, file);
    const dest = join(HOOKS_DEST, file);
    if (existsSync(src)) {
      copyFileSync(src, dest);
      if (file === 'mc-bridge.py') {
        try { execSync(`chmod +x "${dest}"`, { stdio: 'pipe' }); } catch {}
      }
      console.log(`  ✓ Installed ${file}`);
    } else {
      console.log(`  ✗ Missing ${file} — skipped`);
    }
  }

  for (const file of LEGACY_HOOK_FILES) {
    const dest = join(HOOKS_DEST, file);
    if (existsSync(dest)) {
      unlinkSync(dest);
      console.log(`  ✓ Removed legacy ${file}`);
    }
  }

  // Install bridge binary shim
  const shimSrc = join(__dirname, 'mc-bridge');
  const shimDest = join(MC_DIR, 'bin', 'mc-bridge');
  mkdirSync(join(MC_DIR, 'bin'), { recursive: true });
  if (existsSync(shimSrc)) {
    copyFileSync(shimSrc, shimDest);
    try { execSync(`chmod +x "${shimDest}"`, { stdio: 'pipe' }); } catch {}
    console.log('  ✓ Installed mc-bridge launcher shim');
  }

  if (targetAgent) {
    const agent = AGENTS[targetAgent];
    if (agent) {
      if (agent.detect()) { agent.setup(); }
      else { console.log(`  ⚠ ${agent.name} not detected — skipped`); }
    } else {
      console.log(`  ✗ Unknown agent: ${targetAgent}`);
      console.log(`    Available: ${Object.keys(AGENTS).join(', ')}`);
    }
  } else {
    let setupCount = 0;
    for (const [key, agent] of Object.entries(AGENTS)) {
      if (agent.detect()) { agent.setup(); setupCount++; }
    }
    if (setupCount === 0) { console.log('  ⚠ No supported AI agents detected'); }
  }

  console.log('\n  ✅ Setup complete!');

  if (appInstalled && existsSync(APP_PATH)) {
    try {
      execSync(`open "${APP_PATH}"`, { stdio: 'pipe' });
      console.log('  → Mission Control is now running!\n');
    } catch {
      console.log('  → Open Mission Control from /Applications to start.\n');
    }
  }
}

function uninstall() {
  console.log('\n  🗑  Mission Control — Uninstall\n');

  // 1. Remove app
  if (existsSync(APP_PATH)) {
    try {
      execSync(`rm -rf "${APP_PATH}"`, { stdio: 'pipe' });
      console.log('  ✓ Removed Mission Control app');
    } catch {
      console.log('  ⚠ Could not remove app — try: sudo rm -rf /Applications/MissionControl.app');
    }
  }

  // 2. Remove hook files
  if (existsSync(HOOKS_DEST)) {
    for (const file of HOOK_FILES) {
      const dest = join(HOOKS_DEST, file);
      if (existsSync(dest)) {
        unlinkSync(dest);
        console.log(`  ✓ Removed ${file}`);
      }
    }
  }

  // 3. Remove hooks from Claude settings
  if (existsSync(CLAUDE_SETTINGS)) {
    try {
      const settings = JSON.parse(readFileSync(CLAUDE_SETTINGS, 'utf-8'));
      if (settings.hooks) {
        for (const hookName of Object.keys(HOOK_CONFIG.hooks)) {
          if (settings.hooks[hookName]) {
            settings.hooks[hookName] = settings.hooks[hookName].filter(
              (e) => !e.hooks?.some((h) => h.command?.includes('mission-control'))
            );
            if (settings.hooks[hookName].length === 0) {
              delete settings.hooks[hookName];
            }
          }
        }
        if (Object.keys(settings.hooks).length === 0) {
          delete settings.hooks;
        }
        writeFileSync(CLAUDE_SETTINGS, JSON.stringify(settings, null, 2) + '\n');
        console.log('  ✓ Cleaned ~/.claude/settings.json');
      }
    } catch {
      console.log('  ⚠ Could not parse settings.json');
    }
  }

  console.log('\n  ✅ Uninstall complete.\n');
}

function status() {
  const statusFile = join(MC_DIR, 'status.json');
  if (!existsSync(statusFile)) {
    console.log('\n  No active sessions. Start a Claude Code session first.\n');
    return;
  }

  try {
    const agents = JSON.parse(readFileSync(statusFile, 'utf-8'));
    if (!agents.length) {
      console.log('\n  No active sessions.\n');
      return;
    }

    console.log('\n  Mission Control — Active Sessions\n');
    const statusIcons = { running: '🟢', blocked: '🟠', done: '✅', idle: '💤' };
    for (const a of agents) {
      const icon = statusIcons[a.status] || '⚪';
      console.log(`  ${icon} ${a.name} — ${a.status}`);
      if (a.task) console.log(`     ${a.task}`);
    }
    console.log();
  } catch {
    console.log('\n  Could not read status file.\n');
  }
}

// Main
const command = process.argv[2] || 'help';

switch (command) {
  case 'setup':
  case 'install':
    setup();
    break;
  case 'uninstall':
  case 'remove':
    uninstall();
    break;
  case 'status':
    status();
    break;
  default:
    printHelp();
}
