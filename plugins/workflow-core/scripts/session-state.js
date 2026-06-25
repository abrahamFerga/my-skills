#!/usr/bin/env node
// SessionStart hook: orient a session opened inside a generated `the-*` system.
// Injects a one-line status (name, stage, autonomy, repo, objective) + the single
// command to resume. No-ops (exit 0, no output) anywhere there is no workflow.json,
// so it is invisible in this marketplace repo and any non-generated project.
'use strict';
const fs = require('fs');
const path = require('path');

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (_) { return ''; }
}
function loadJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; }
}

try {
  let input = {};
  try { input = JSON.parse(readStdin() || '{}'); } catch (_) {}
  const cwd = input.cwd || process.cwd();
  const wf = loadJson(path.join(cwd, 'workflow.json'));
  if (!wf) process.exit(0); // not a generated system

  const stage = wf.stage || 'system-definition';
  const autonomy = (wf.goal && wf.goal.autonomy) || 'confirm';
  const objective = (wf.goal && wf.goal.objective) || null;
  const repo = wf.github && wf.github.repo ? wf.github.repo : '(local — GitHub not wired)';

  const lines = [
    'Generated system **' + (wf.name || '?') + '** (' + (wf.industry || '?') + ') — stage **' +
      stage + '**, autonomy **' + autonomy + '**, repo ' + repo + '.',
    objective ? 'Goal: ' + objective : null,
    'Resume hands-off with `/workflow-core:build-generated-system` (no args — it infers the ' +
      'current phase from the files and the board and continues from the first unmet one).',
  ].filter(Boolean);

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: lines.join('\n'),
    },
  }));
} catch (_) {
  // fail silent
}
process.exit(0);
