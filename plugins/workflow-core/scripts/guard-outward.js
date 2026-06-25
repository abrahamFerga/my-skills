#!/usr/bin/env node
// PreToolUse(Bash) guard for generated `the-*` systems.
// Blocks irreversible outward git/gh actions; otherwise defers to the normal
// permission flow. No-ops (exit 0) when the cwd is not a generated system, and
// fails OPEN on any internal error — a buggy guard must never brick the workflow.
// Gated by hooks.json `if` patterns so node only spawns for git push / gh pr merge / gh api merge.
'use strict';
const fs = require('fs');
const path = require('path');

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (_) { return ''; }
}
function loadJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; }
}
function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
}

try {
  let input = {};
  try { input = JSON.parse(readStdin() || '{}'); } catch (_) { process.exit(0); }

  const cmd = (input.tool_input && input.tool_input.command) || '';
  if (!cmd) process.exit(0);

  // Only meaningful inside a generated system; invisible everywhere else.
  const wf = loadJson(path.join(input.cwd || process.cwd(), 'workflow.json'));
  if (!wf) process.exit(0);

  const autonomy = (wf.goal && wf.goal.autonomy) || 'confirm';
  const c = cmd.replace(/\s+/g, ' ').trim();

  // 1) Force-push — forbidden outright in this workflow (rewrites shared history).
  if (/(^|[;&|]\s*)git\s+push\b/.test(c)) {
    const forced =
      /\s(-f|--force|--force-with-lease(=\S*)?)\b/.test(c) ||
      /\spush\b[^\n]*\s\+[\w./@~^-]+(:|$|\s)/.test(c); // +refspec
    if (forced) {
      deny(
        'Force-pushing is forbidden in this workflow — it can rewrite shared history. ' +
        'Push your feature branch normally; if it diverged, reconcile locally with a merge or ' +
        'rebase and push a fresh commit. (Guard: workflow-core)'
      );
    }
    // Deletion of the default branch on the remote — deny only when the TARGET ref is exactly
    // main/master, so feature branches like `main-fix` / `master-data` are not false-blocked.
    let del = null, m;
    if ((m = /\s--delete\s+(?:[^\s:]+\s+)?(\S+)\s*$/.exec(c))) del = m[1];   // git push [remote] --delete <branch>
    else if ((m = /\spush\b[^\n]*\s:(\S+)/.exec(c))) del = m[1];            // git push origin :<branch>
    if (del) {
      const b = del.replace(/^refs\/heads\//, '');
      if (b === 'main' || b === 'master') {
        deny('Deleting the default branch on the remote is forbidden. (Guard: workflow-core)');
      }
    }
  }

  // 2) Merging a PR is a reviewed action unless the run is explicitly autonomy=auto.
  //    Covers both `gh pr merge` and the REST form `gh api .../pulls/<n>/merge`.
  const isMerge =
    /(^|[;&|]\s*)gh\s+pr\s+merge\b/.test(c) ||
    (/(^|[;&|]\s*)gh\s+api\b/.test(c) && /pulls\/\d+\/merge\b/.test(c));
  if (isMerge && autonomy !== 'auto') {
    deny(
      'Merging a PR is a reviewed action. This run is autonomy=' + autonomy + ' — open the PR ' +
      'and let a human (or repo auto-merge) merge it. To let the agent merge, set autonomy=auto ' +
      'via /workflow-core:goal. (Guard: workflow-core)'
    );
  }
} catch (_) {
  // fail open
}
process.exit(0);
