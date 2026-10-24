'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const ai = require('../AI-Commit.cjs');
const actions = require('../Repo-Actions.cjs');
const workstation = path.resolve(__dirname, '../..');
function fixture() {
  const base = path.join(workstation, 'Data/Temp'); fs.mkdirSync(base, { recursive: true });
  return fs.mkdtempSync(path.join(base, 'ai-tests-'));
}
function mockContext(root, behavior = 'success') {
  const exe = path.join(root, 'mock-cli.exe'); fs.writeFileSync(exe, 'synthetic fixture');
  const calls = [], attachments = [];
  return { root, env: {}, openCodeExe: exe, calls, attachments,
    openCodeRun: async (file, args, box) => {
      calls.push(args);
      assert.equal(box.env.OPENCODE_CONFIG, undefined);
      const settings = JSON.parse(fs.readFileSync(path.join(box.cwd, 'opencode.json')));
      assert.deepEqual(settings.permissions, [{ action: '*', resource: '*', effect: 'deny' }]);
      assert.ok(settings.policies.some(p => p.action === 'integration.use' && p.effect === 'deny'));
      if (args[0] === 'auth') return { code: 0, stdout: behavior === 'noauth' ? '[]' : '[{"provider":"opencode"}]' };
      if (args[0] === 'models') return { code: 0, stdout: behavior === 'paid' ? 'opencode/paid-model' : ai.FREE_MODELS[0] };
      assert.equal(args[args.indexOf('--model') + 1], ai.FREE_MODELS[0]);
      assert.ok(args.includes('--standalone')); assert.ok(args.includes('--title'));
      const prompt = args[args.indexOf('--file') + 1]; attachments.push(prompt);
      assert.ok(fs.readFileSync(prompt, 'utf8').includes('Untrusted change data'));
      return behavior === 'denied' ? { code: 1, stdout: '{"type":"error"}' } :
        { code: 0, stdout: JSON.stringify({ type: 'text', part: { text: 'Improve portable browser routing' } }) + '\n' };
    } };
}
test('requires saved login and an explicit free catalog entry; never tries paid fallback', async () => {
  for (const behavior of ['noauth', 'paid']) {
    const ctx = mockContext(fixture(), behavior), ready = await ai.detect(ctx);
    assert.equal(ready.available, false); assert.ok(!ctx.calls.some(args => args[0] === 'run'));
    if (behavior === 'noauth') assert.equal(ctx.calls.length, 1);
  }
  assert.equal((await ai.detect({ root: fixture() })).available, false);
});
test('isolates config, denies tools, uses attachment and removes the temporary prompt', async () => {
  const ctx = mockContext(fixture()), ready = await ai.detect(ctx);
  assert.equal(ready.available, true);
  const generated = await ai.generate(ctx, ready, { files: [{ code: ' M', name: 'README.md' }], diff: '+Document browser routing' });
  assert.equal(generated.subject, 'Improve portable browser routing');
  assert.ok(ctx.attachments.every(file => !fs.existsSync(file)));
  assert.ok(!ctx.calls.flat().some(arg => arg.includes('+Document browser routing')));
});
test('provider rejection cleans attachment and makes no second model request', async () => {
  const ctx = mockContext(fixture(), 'denied'), ready = await ai.detect(ctx);
  await assert.rejects(ai.generate(ctx, ready, { files: [], diff: 'synthetic' }), /manuelle Nachricht/);
  assert.equal(ctx.calls.filter(args => args[0] === 'run').length, 1);
  assert.ok(ctx.attachments.every(file => !fs.existsSync(file)));
});
test('refuses private filenames, credential patterns, huge data and invalid model responses', () => {
  for (const name of ['.env', 'data/Cookies', 'Login Data', 'auth.json']) assert.throws(() => ai.prompt({ files: [{ code: '??', name }], diff: 'synthetic' }));
  const token = ['gh', 'p_'].join('') + 'x'.repeat(40);
  assert.throws(() => ai.prompt({ files: [], diff: token }));
  assert.throws(() => ai.prompt({ files: [], diff: 'x'.repeat(14001) }));
  for (const response of [{ type: 'error' }, { type: 'text', part: { text: 'one\ntwo' } }, { type: 'step_finish', part: { cost: 0.1 } }]) assert.throws(() => ai.parseOutput(JSON.stringify(response)));
});
const gitExe = process.env.GIT_TEST_EXE || 'git';
function localGit(repo, args) {
  const out = spawnSync(gitExe, ['-c', 'safe.directory=*', '-C', repo, ...args], { encoding: 'utf8', windowsHide: true });
  assert.equal(out.status, 0, out.stderr); return out.stdout.trim();
}
function repositories(root) {
  const repo = path.join(root, 'GitRepos/project'), remote = path.join(root, 'remote.git');
  fs.mkdirSync(repo, { recursive: true }); fs.mkdirSync(remote);
  localGit(remote, ['init', '--bare']); localGit(repo, ['init', '-b', 'main']);
  localGit(repo, ['config', 'user.name', 'Synthetic Test']); localGit(repo, ['config', 'user.email', 'test@example.invalid']);
  fs.writeFileSync(path.join(repo, 'notes.txt'), 'initial\n');
  localGit(repo, ['add', '.']); localGit(repo, ['commit', '-m', 'Initial fixture']);
  localGit(repo, ['remote', 'add', 'origin', remote]); localGit(repo, ['push', '-u', 'origin', 'main']);
  fs.writeFileSync(path.join(repo, 'notes.txt'), 'initial\nsynthetic improvement\n');
  return { repo, remote };
}
test('real local Git commit and push use generated subject only after SENDEN', async () => {
  const root = fixture(), { repo, remote } = repositories(root), mock = mockContext(root), answers = ['alle', '', 'SENDEN'];
  const ctx = actions.createContext({ ...mock, gitExe, log() {}, ask: async () => answers.shift() });
  const out = await actions.runPublish(ctx);
  assert.equal(out.counts.pushed, 1);
  assert.equal(localGit(repo, ['log', '-1', '--format=%s']), 'Improve portable browser routing');
  assert.equal(localGit(repo, ['rev-parse', 'HEAD']), localGit(remote, ['rev-parse', 'main']));
});
test('cancel keeps HEAD unchanged; changed bytes invalidate otherwise identical status preview', async () => {
  const root = fixture(), { repo } = repositories(root), mock = mockContext(root), answers = ['alle', '', ''];
  const ctx = actions.createContext({ ...mock, gitExe, log() {}, ask: async () => answers.shift() });
  const head = localGit(repo, ['rev-parse', 'HEAD']);
  assert.equal((await actions.runPublish(ctx)).cancelled, true);
  assert.equal(localGit(repo, ['rev-parse', 'HEAD']), head);
  const state = await actions.pushDetails(ctx, await actions.repoState(ctx, repo));
  fs.appendFileSync(path.join(repo, 'notes.txt'), 'changed during review\n');
  const result = await actions.publishRepo(ctx, state, 'Must not commit');
  assert.equal(result.outcome, 'skipped'); assert.equal(localGit(repo, ['rev-parse', 'HEAD']), head);
});
test('CLI auth failure falls back to manual subject and still requires SENDEN', async () => {
  const root = fixture(), { repo } = repositories(root), mock = mockContext(root, 'denied'), answers = ['alle', '', 'Use manual subject', 'SENDEN'];
  const ctx = actions.createContext({ ...mock, gitExe, log() {}, ask: async () => answers.shift() });
  assert.equal((await actions.runPublish(ctx)).counts.pushed, 1);
  assert.equal(localGit(repo, ['log', '-1', '--format=%s']), 'Use manual subject');
});
