#!/usr/bin/env node
'use strict';

const { spawn } = require('child_process');
const path = require('path');

if (process.platform !== 'win32') {
  console.error('WinPortableLab supports Windows only. Run it on Windows 10/11 with PowerShell 5.1 or later.');
  process.exit(1);
}

const root = path.resolve(__dirname, '..');
const entry = path.join(root, 'WinPortableLab.ps1');
const args = [
  '-NoLogo',
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  entry,
  ...process.argv.slice(2)
];

const child = spawn('powershell.exe', args, {
  stdio: 'inherit',
  windowsHide: false
});

child.on('error', (error) => {
  console.error('Failed to launch Windows PowerShell:', error.message);
  process.exit(1);
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.exit(1);
  }
  process.exit(typeof code === 'number' ? code : 1);
});
