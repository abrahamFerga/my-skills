#!/usr/bin/env node
// Stop hook: self-continue an autonomy=auto run for a generated `the-*` system.
// Strictly opt-in — does nothing unless workflow.json has goal.autonomy === "auto".
// A git-HEAD circuit breaker stops a stuck loop: if no new commit lands for CAP
// consecutive stop attempts, it lets the session stop. Only re-drives sessions whose
// transcript shows build-pipeline activity, so an ad-hoc session opened in an auto
// project is never hijacked. Fails open on any error.
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const CAP = 40; // consecutive stop attempts with no new commit before giving up

// Transient counter lives in the OS temp dir (keyed by project path), NEVER in the
// project tree — otherwise `git add -A` would commit it into a feature PR.
function stateFileFor(cwd) {
  const key = cwd.replace(/[^a-zA-Z0-9]+/g, '_').slice(-80);
  return path.join(os.tmpdir(), 'mskills-autoloop-' + key + '.json');
}

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (_) { return ''; }
}
function loadJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; }
}
function gitHead(cwd) {
  try {
    return execSync('git rev-parse HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'] })
      .toString().trim();
  } catch (_) { return ''; }
}

try {
  let input = {};
  try { input = JSON.parse(readStdin() || '{}'); } catch (_) { process.exit(0); }

  // Only re-drive the main loop, never a subagent's Stop.
  if (input.agent_id || input.agent_type) process.exit(0);

  const cwd = input.cwd || process.cwd();
  const wf = loadJson(path.join(cwd, 'workflow.json'));
  if (!wf || !wf.goal || wf.goal.autonomy !== 'auto') process.exit(0); // opt-in only

  // Re-drive ONLY a session that is actually running the build pipeline — never hijack an
  // ad-hoc session that merely happens to be opened in an autonomy=auto project. Evidence =
  // the conductor or a pipeline agent appearing in the recent transcript tail.
  const tpath = input.transcript_path;
  if (tpath) {
    let recent = '';
    try {
      const buf = fs.readFileSync(tpath);
      recent = buf.slice(Math.max(0, buf.length - 65536)).toString('utf8');
    } catch (_) { recent = ''; }
    if (!/build-generated-system|work-next-issue|feature-builder|runtime-verifier|backlog-manager/.test(recent)) {
      process.exit(0); // not a build session -> let it stop normally
    }
  }

  const stopWhen = wf.goal.stop_when || 'backlog-drained';

  // Circuit breaker keyed on real progress (a new commit resets the counter).
  const stateFile = stateFileFor(cwd);
  const head = gitHead(cwd);
  let st = loadJson(stateFile) || { n: 0, head: '' };
  if (head && head !== st.head) st = { n: 0, head: head }; // progress -> reset
  st.n = (st.n || 0) + 1;
  try { fs.writeFileSync(stateFile, JSON.stringify(st)); } catch (_) {}

  if (st.n > CAP) {
    try { fs.writeFileSync(stateFile, JSON.stringify({ n: 0, head: head })); } catch (_) {}
    process.stdout.write(JSON.stringify({
      systemMessage:
        'autonomy=auto made no progress for ' + CAP + ' iterations — stopping to avoid a runaway ' +
        'loop. Re-run /loop /workflow-core:build-generated-system once the blocker is cleared.',
    }));
    process.exit(0);
  }

  const stopClause =
    stopWhen === 'backlog-drained' ? 'every feature issue is Done' :
    stopWhen === 'stage-complete' ? 'the current stage is finished' :
    'never — only an external Esc / stop';

  const reason =
    'Autonomy is `auto` (stop_when=' + stopWhen + '). If unfinished work remains and nothing is ' +
    'blocked, CONTINUE now: re-orient from workflow.json and the GitHub board, then advance the ' +
    'next phase or feature via /workflow-core:build-generated-system (build → verify → PR), one ' +
    'unit in flight. STOP and report instead if ANY of these holds: the stop condition is met (' +
    stopClause + '); a phase needs a human decision (an unanswered research question, a guardrail ' +
    'conflict, or an action autonomy=auto still forbids such as force-push); or the same step just ' +
    'failed twice. Never loop on a failure — surface it.';

  process.stdout.write(JSON.stringify({ decision: 'block', reason: reason }));
} catch (_) {
  // fail open -> allow the stop
}
process.exit(0);
