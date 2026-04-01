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
const HOOKS_DEST = join(MC_DIR, 'hooks');
const CLAUDE_SETTINGS = join(homedir(), '.claude', 'settings.json');
const APP_PATH = '/Applications/MissionControl.app';
const DOWNLOAD_URL = 'https://github.com/alexko0421/MissionControl/releases/latest/download/MissionControl.zip';

const HOOK_FILES = [
  'mc-claude-hook.py',
  'mc-prompt-hook.py',
  'mc-pretool-hook.py',
  'mc-posttool-hook.py',
];

const HOOK_CONFIG = {
  hooks: {
    Stop: [
      {
        matcher: '',
        hooks: [
          {
            type: 'command',
            command: `python3 ${join(HOOKS_DEST, 'mc-claude-hook.py')}`,
          },
        ],
      },
    ],
    UserPromptSubmit: [
      {
        matcher: '',
        hooks: [
          {
            type: 'command',
            command: `python3 ${join(HOOKS_DEST, 'mc-prompt-hook.py')}`,
          },
        ],
      },
    ],
    PreToolUse: [
      {
        matcher: '',
        hooks: [
          {
            type: 'command',
            command: `python3 ${join(HOOKS_DEST, 'mc-pretool-hook.py')}`,
          },
        ],
      },
    ],
    PostToolUse: [
      {
        matcher: '',
        hooks: [
          {
            type: 'command',
            command: `python3 ${join(HOOKS_DEST, 'mc-posttool-hook.py')}`,
          },
        ],
      },
    ],
  },
};

function printHelp() {
  console.log(`
  Mission Control — monitor AI coding sessions in real time

  Usage:
    npx mission-control-ai setup      Install app + hooks
    npx mission-control-ai uninstall   Remove app + hooks
    npx mission-control-ai status      Show current session status
    npx mission-control-ai help        Show this help
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

function setup() {
  console.log('\n  🚀 Mission Control — Setup\n');

  // 1. Install the app
  const appInstalled = installApp();

  // 2. Create directories
  mkdirSync(HOOKS_DEST, { recursive: true });
  mkdirSync(dirname(CLAUDE_SETTINGS), { recursive: true });
  console.log('  ✓ Created ~/.mission-control/hooks/');

  // 3. Copy hook scripts
  for (const file of HOOK_FILES) {
    const src = join(HOOKS_SRC, file);
    const dest = join(HOOKS_DEST, file);
    if (existsSync(src)) {
      copyFileSync(src, dest);
      console.log(`  ✓ Installed ${file}`);
    } else {
      console.log(`  ✗ Missing ${file} — skipped`);
    }
  }

  // 4. Configure Claude Code settings
  let settings = {};
  if (existsSync(CLAUDE_SETTINGS)) {
    try {
      settings = JSON.parse(readFileSync(CLAUDE_SETTINGS, 'utf-8'));
    } catch {
      console.log('  ⚠ Could not parse existing settings.json — creating new one');
    }
  }

  if (!settings.hooks) settings.hooks = {};

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

  writeFileSync(CLAUDE_SETTINGS, JSON.stringify(settings, null, 2) + '\n');
  console.log('  ✓ Updated ~/.claude/settings.json');

  console.log('\n  ✅ Setup complete!');

  // 5. Launch the app
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
