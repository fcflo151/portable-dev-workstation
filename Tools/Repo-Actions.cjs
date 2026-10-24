'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const aiCommit = require('./AI-Commit.cjs');

function safeText(value) {
  return String(value).replace(/((?:https?|ssh):\/\/)[^\s/@]+@/gi, '$1[Zugangsdaten entfernt]@')
    .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, '?');
}
function createContext(options = {}) {
  const root = path.resolve(options.root || path.join(__dirname, '..'));
  // Also cover direct PowerShell/Node launches without Portable-Env.cmd.
  const env = { ...process.env, ...options.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'Never', GIT_OPTIONAL_LOCKS: '0' };
  env.GIT_CONFIG_COUNT = '1';
  env.GIT_CONFIG_KEY_0 = 'safe.directory';
  env.GIT_CONFIG_VALUE_0 = path.join(root, 'GitRepos').replaceAll('\\', '/') + '/*';
  return {
    root, reposDir: path.join(root, 'GitRepos'),
    gitExe: options.gitExe || path.join(root, 'Apps', fs.existsSync(path.join(root, 'Apps/Git/cmd/git.exe')) ? 'Git' : 'PortableGit', 'cmd', 'git.exe'),
    ghExe: options.ghExe || path.join(root, 'Apps', 'gh', 'gh.exe'),
    env,
    timeout: options.timeout || 120000, log: options.log || (text => console.log(safeText(text))),
    ask: options.ask, discover: options.discover,
    openCodeExe: options.openCodeExe, openCodeRun: options.openCodeRun, aiTimeout: options.aiTimeout
  };
}
function run(ctx, exe, args, timeout = ctx.timeout) {
  return new Promise(resolve => {
    const child = spawn(exe, args, { env: ctx.env, windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    const stdout = [], stderr = []; let size = 0, failure = '', settled = false;
    function finish(code) {
      if (settled) return; settled = true; clearTimeout(timer);
      resolve({ code: failure ? -1 : code, stdout: Buffer.concat(stdout).toString('utf8'), stderr: failure || Buffer.concat(stderr).toString('utf8') });
    }
    function stop(message) {
      failure = message;
      if (process.platform === 'win32' && child.pid) {
        const killer = spawn(path.join(process.env.SystemRoot, 'System32', 'taskkill.exe'), ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
        killer.on('error', () => child.kill());
      } else child.kill();
      finish(-1);
    }
    const timer = setTimeout(() => stop('Zeitlimit fuer Git-Aufruf erreicht.'), timeout);
    for (const [stream, chunks] of [[child.stdout, stdout], [child.stderr, stderr]]) stream.on('data', data => {
      size += data.length;
      if (size > 16 * 1024 * 1024) { if (!settled) stop('Git-Ausgabe zu gross; Repository bitte manuell pruefen.'); }
      else if (!settled) chunks.push(data);
    });
    child.once('error', error => { failure = error.message; finish(-1); });
    child.once('close', code => finish(code == null ? -1 : code));
  });
}
async function git(ctx, repo, args) {
  return run(ctx, ctx.gitExe, ['-c', 'core.quotepath=false', '-C', repo, ...args]);
}
async function checked(ctx, repo, args) {
  const result = await git(ctx, repo, args);
  if (result.code !== 0) throw new Error(safeText((result.stderr || result.stdout || 'Git-Aufruf fehlgeschlagen.').trim()));
  return result.stdout.trim();
}
function samePath(a, b) {
  const normalize = v => path.resolve(v).replaceAll('\\', '/').replace(/\/$/, '').toLowerCase();
  return normalize(a) === normalize(b);
}
function localRepos(ctx) {
  fs.mkdirSync(ctx.reposDir, { recursive: true });
  return fs.readdirSync(ctx.reposDir, { withFileTypes: true })
    .filter(item => item.isDirectory() && !item.isSymbolicLink() && item.name !== '.git')
    .map(item => ({ name: item.name, target: path.join(ctx.reposDir, item.name) }))
    .filter(item => fs.existsSync(path.join(item.target, '.git')))
    .sort((a, b) => a.name.localeCompare(b.name, 'de'));
}
function parseStatus(raw) {
  const tokens = raw.split('\0'), files = [];
  for (let i = 0; i < tokens.length; i++) {
    if (!tokens[i]) continue;
    const code = tokens[i].slice(0, 2), name = tokens[i].slice(3);
    const original = /[RC]/.test(code) ? tokens[++i] : null;
    files.push({ code, name, original });
  }
  return files;
}
function sensitivePath(file) {
  const base = path.posix.basename(file.replaceAll('\\', '/')).toLowerCase();
  return (/^\.env(?:\.|$)/.test(base) && !/^\.env\.(?:example|sample|template)(?:\.|$)/.test(base)) ||
    /^(?:id_rsa|id_ed25519|id_ecdsa|credentials\.json|auth\.json)$/.test(base) || /\.(?:p12|pfx|key)$/.test(base);
}
async function repoState(ctx, target) {
  if (!samePath(path.dirname(target), ctx.reposDir) || !fs.existsSync(path.join(target, '.git'))) throw new Error('Kein einzelnes Projekt direkt unter GitRepos.');
  if (!samePath(fs.realpathSync(target), target)) throw new Error('Verknuepfte Projektordner werden nicht automatisch bearbeitet.');
  const top = await checked(ctx, target, ['rev-parse', '--show-toplevel']);
  if (!samePath(top, target)) throw new Error('Ordner ist kein eigenstaendiges Repository.');
  const gitDir = await checked(ctx, target, ['rev-parse', '--path-format=absolute', '--git-dir']);
  for (const marker of ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer', 'BISECT_LOG']) {
    if (fs.existsSync(path.join(gitDir, marker))) throw new Error('Laufender Merge/Rebase oder andere Git-Operation; bitte zuerst abschliessen.');
  }
  const branchResult = await git(ctx, target, ['symbolic-ref', '--quiet', '--short', 'HEAD']);
  if (branchResult.code !== 0) throw new Error('Kein aktiver Branch (detached HEAD); bitte im Terminal einen Branch waehlen.');
  const branch = branchResult.stdout.trim();
  const head = await checked(ctx, target, ['rev-parse', '--verify', 'HEAD']);
  const raw = await git(ctx, target, ['status', '--porcelain=v1', '-z', '--untracked-files=all']);
  if (raw.code !== 0) throw new Error(safeText(raw.stderr));
  const files = parseStatus(raw.stdout);
  if (files.some(file => ['DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'].includes(file.code))) throw new Error('Ungueloeste Git-Konflikte; bitte zuerst aufloesen.');
  const tracking = await checked(ctx, target, ['for-each-ref', '--format=%(upstream:remotename)%09%(upstream:remoteref)', 'refs/heads/' + branch]);
  const [remote, remoteRef] = tracking.split('\t');
  if (!remote || remote === '.' || !remoteRef || !remoteRef.startsWith('refs/heads/')) throw new Error('Kein Remote-Upstream fuer den aktuellen Branch; bitte einmal im Terminal einrichten.');
  const upstream = await checked(ctx, target, ['rev-parse', '--symbolic-full-name', '@{upstream}']);
  const upstreamOid = await checked(ctx, target, ['rev-parse', '--verify', '@{upstream}']);
  const counts = await checked(ctx, target, ['rev-list', '--left-right', '--count', 'HEAD...@{upstream}']);
  const [ahead, behind] = counts.split(/\s+/).map(Number);
  if (!Number.isInteger(ahead) || !Number.isInteger(behind)) throw new Error('Git-Stand konnte nicht ermittelt werden.');
  return { target, name: path.basename(target), branch, head, files, raw: raw.stdout, remote, remoteRef, upstream, upstreamOid, ahead, behind };
}
function result(name, outcome, message, extra = {}) { return { name, outcome, message: safeText(message), ...extra }; }
async function updateRepo(ctx, target) {
  const name = path.basename(target);
  try {
    const state = await repoState(ctx, target);
    if (state.files.length) return result(name, 'skipped', 'Lokale Aenderungen vorhanden; unveraendert gelassen.');
    await checked(ctx, target, ['fetch', '--prune', '--', state.remote]);
    const current = await repoState(ctx, target);
    if (current.head !== state.head || current.raw !== state.raw || current.remote !== state.remote || current.remoteRef !== state.remoteRef) return result(name, 'skipped', 'Projekt wurde waehrend der Pruefung geaendert.');
    if (current.ahead && current.behind) return result(name, 'skipped', 'Lokaler und Remote-Branch auseinander gelaufen; manuell zusammenfuehren.');
    if (!current.behind) return result(name, 'current', current.ahead ? 'Lokal voraus; vorhandene Commits bleiben erhalten.' : 'Bereits aktuell.');
    await checked(ctx, target, ['merge', '--ff-only', '--', current.upstream]);
    return result(name, 'updated', 'Per Fast-forward aktualisiert.');
  } catch (error) { return result(name, 'failed', error.message); }
}
async function pushDetails(ctx, state) {
  const urls = (await checked(ctx, state.target, ['remote', 'get-url', '--push', '--all', state.remote])).split(/\r?\n/).filter(Boolean);
  if (urls.length !== 1) throw new Error('Mehrere Push-Ziele konfiguriert; bitte manuell senden.');
  const mirror = await git(ctx, state.target, ['config', '--bool', '--get', 'remote.' + state.remote + '.mirror']);
  if (mirror.code === 0 && mirror.stdout.trim() === 'true') throw new Error('Mirror-Remote wird nicht automatisch gepusht.');
  if (mirror.code !== 0 && mirror.code !== 1) throw new Error('Remote-Konfiguration konnte nicht gelesen werden.');
  const outgoing = state.ahead ? await checked(ctx, state.target, ['diff', '--name-only', '-z', '--diff-filter=ACMR', '@{upstream}..HEAD']) : '';
  const sensitive = [...new Set([...state.files.filter(f => !/^D |^ D$/.test(f.code)).map(f => f.name), ...outgoing.split('\0').filter(Boolean)].filter(sensitivePath))];
  if (sensitive.length) throw new Error('Moegliche Zugangsdaten/Schluessel in Dateiliste: ' + sensitive.map(safeText).join(', ') + '. Bitte separat pruefen.');
  const commits = state.ahead ? await checked(ctx, state.target, ['log', '--max-count=8', '--format=%h %s', '@{upstream}..HEAD']) : '';
  return { ...state, pushUrl: urls[0], commits, fingerprint: await fingerprint(ctx, state), worktreeFingerprint: await fingerprint(ctx, state, false) };
}
async function fingerprint(ctx, state, includeIndex = true) {
  const hash = crypto.createHash('sha256');
  // Include staged object IDs as well as current bytes: porcelain alone misses edits
  // to an already-modified file while the user reviews a generated message.
  if (includeIndex) hash.update(await checked(ctx, state.target, ['diff', '--cached', '--raw', '--no-abbrev', '--no-ext-diff']));
  for (const file of state.files) {
    hash.update(JSON.stringify(file));
    const absolute = path.resolve(state.target, file.name);
    if (!absolute.startsWith(state.target + path.sep)) throw new Error('Ungueltiger Dateipfad.');
    let stat; try { stat = fs.lstatSync(absolute); } catch (error) { if (error.code === 'ENOENT') { hash.update('deleted'); continue; } throw error; }
    if (!stat.isFile() || stat.isSymbolicLink() || !samePath(fs.realpathSync(absolute), absolute)) throw new Error('Verknuepfungen und Unterprojekte bitte manuell committen.');
    hash.update(String(stat.mode));
    for await (const chunk of fs.createReadStream(absolute)) hash.update(chunk);
  }
  return hash.digest('hex');
}
async function aiChanges(ctx, state) {
  const diff = await checked(ctx, state.target, ['diff', '--no-ext-diff', '--no-textconv', '--no-color', '--no-renames', '-U0', 'HEAD', '--']);
  let text = diff;
  for (const file of state.files.filter(file => file.code === '??')) {
    const absolute = path.resolve(state.target, file.name), stat = fs.lstatSync(absolute);
    if (!stat.isFile() || stat.isSymbolicLink() || !samePath(fs.realpathSync(absolute), absolute) || stat.size > 14000) throw new Error('Neue Datei nicht fuer KI-Vorschau geeignet.');
    const bytes = fs.readFileSync(absolute);
    if (bytes.includes(0) || !Buffer.from(bytes.toString('utf8')).equals(bytes)) throw new Error('Binaerdatei nicht fuer KI-Vorschau geeignet.');
    text += '\nNew file: ' + JSON.stringify(file.name) + '\n' + bytes.toString('utf8');
  }
  if (await fingerprint(ctx, state) !== state.fingerprint) throw new Error('Dateien seit der Vorschau geaendert.');
  return { files: state.files, diff: text };
}
async function publishRepo(ctx, expected, message) {
  let commitCreated = false, publishHead = expected.head;
  try {
    await checked(ctx, expected.target, ['fetch', '--prune', '--', expected.remote]);
    const state = await pushDetails(ctx, await repoState(ctx, expected.target));
    if (state.behind) return result(state.name, 'skipped', 'Remote enthaelt neue Commits; erst aktualisieren bzw. manuell zusammenfuehren.');
    for (const field of ['head', 'branch', 'raw', 'remote', 'remoteRef', 'upstreamOid', 'pushUrl', 'fingerprint']) {
      if (state[field] !== expected[field]) return result(state.name, 'skipped', 'Stand seit der Vorschau geaendert; bitte Vorschau erneut oeffnen.');
    }
    if (state.files.length) {
      const paths = [...new Set(state.files.flatMap(f => f.original ? [f.name, f.original] : [f.name]))];
      const trackedResult = await git(ctx, state.target, ['ls-files', '-z']);
      if (trackedResult.code !== 0) throw new Error(trackedResult.stderr);
      const tracked = new Set(trackedResult.stdout.split('\0'));
      const stagePaths = paths.filter(file => {
        if (tracked.has(file)) return true;
        try { fs.lstatSync(path.join(state.target, file)); return true; } catch { return false; }
      });
      const tempDir = path.join(ctx.root, 'Data', 'Temp'); fs.mkdirSync(tempDir, { recursive: true });
      const spec = path.join(tempDir, 'repo-paths-' + crypto.randomUUID() + '.nul');
      try {
        if (stagePaths.length) {
          fs.writeFileSync(spec, Buffer.from(stagePaths.join('\0') + '\0', 'utf8'));
          await checked(ctx, state.target, ['--literal-pathspecs', 'add', '-A', '--pathspec-from-file=' + spec, '--pathspec-file-nul']);
        }
      } finally { if (fs.existsSync(spec)) fs.unlinkSync(spec); }
      const stagedRaw = await git(ctx, state.target, ['diff', '--cached', '--name-only', '-z']);
      if (stagedRaw.code !== 0) throw new Error(stagedRaw.stderr);
      const staged = stagedRaw.stdout.split('\0').filter(Boolean);
      if (staged.some(file => !paths.includes(file))) throw new Error('Weitere Dateien wurden gleichzeitig vorgemerkt; kein Commit erstellt.');
      if (staged.length) {
        if (await fingerprint(ctx, state, false) !== expected.worktreeFingerprint) throw new Error('Dateien wurden waehrend des Vormerkens geaendert; kein Commit erstellt.');
        const stagedDiff = await checked(ctx, state.target, ['diff', '--no-ext-diff', '--name-only', '--']);
        if (stagedDiff) throw new Error('Dateien wurden waehrend des Vormerkens geaendert; kein Commit erstellt.');
        if ((await checked(ctx, state.target, ['rev-parse', 'HEAD'])) !== state.head || (await checked(ctx, state.target, ['symbolic-ref', '--short', 'HEAD'])) !== state.branch) throw new Error('Branch oder Commit wurde gleichzeitig geaendert; kein Commit erstellt.');
        await checked(ctx, state.target, ['commit', '-m', message]); commitCreated = true;
        publishHead = await checked(ctx, state.target, ['rev-parse', 'HEAD']);
      }
    }
    const current = await repoState(ctx, state.target);
    if (current.branch !== state.branch || current.remote !== state.remote || current.remoteRef !== state.remoteRef) throw new Error('Branch/Upstream wurde gleichzeitig geaendert; Push abgebrochen.');
    const finalDetails = await pushDetails(ctx, current);
    if (finalDetails.pushUrl !== state.pushUrl || current.head !== publishHead) throw new Error('Push-Ziel oder lokaler Commit wurde gleichzeitig geaendert; Push abgebrochen.');
    if (!current.ahead) return result(state.name, 'current', 'Keine ungesendeten Commits.', { commitCreated });
    await checked(ctx, state.target, ['-c', 'push.followTags=false', '-c', 'push.recurseSubmodules=no', 'push', '--porcelain', '--', state.remote, publishHead + ':' + state.remoteRef]);
    return result(state.name, 'pushed', 'Commits an ' + state.remote + '/' + state.remoteRef.slice(11) + ' gesendet.', { commitCreated });
  } catch (error) { return result(expected.name, 'failed', (commitCreated ? 'Commit bleibt lokal erhalten. ' : '') + error.message, { commitCreated }); }
}
function acquireLock(ctx) {
  const dir = path.join(ctx.root, 'Data', 'Locks'); fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'repo-actions.lock');
  const owner = JSON.stringify({ pid: process.pid, host: os.hostname(), token: crypto.randomUUID() });
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const handle = fs.openSync(file, 'wx'); fs.writeFileSync(handle, owner); fs.closeSync(handle);
      return () => { try { if (fs.readFileSync(file, 'utf8') === owner) fs.unlinkSync(file); } catch {} };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const existing = fs.readFileSync(file, 'utf8'); let previous;
      try { previous = JSON.parse(existing); } catch { throw new Error('Repo-Sperre ist unlesbar: ' + file); }
      let alive = previous.host === os.hostname();
      if (alive) { try { process.kill(previous.pid, 0); } catch (e) { if (e.code === 'ESRCH') alive = false; } }
      if (alive) throw new Error('Eine Repo-Aktion laeuft bereits. Bitte deren Fenster abwarten.');
      if (fs.readFileSync(file, 'utf8') !== existing) throw new Error('Repo-Sperre wurde gerade geaendert.');
      fs.unlinkSync(file);
    }
  }
  throw new Error('Repo-Sperre konnte nicht erstellt werden.');
}
function report(ctx, action, results, cancelled = false) {
  const counts = {};
  const labels = { current: 'Aktuell', updated: 'Aktualisiert', cloned: 'Neu geklont', skipped: 'Uebersprungen', failed: 'Fehler', pushed: 'Gesendet' };
  for (const item of results) { counts[item.outcome] = (counts[item.outcome] || 0) + 1; ctx.log('[' + labels[item.outcome] + '] ' + item.name + ': ' + item.message); }
  const log = { time: new Date().toISOString(), action, cancelled, counts, results };
  const dir = path.join(ctx.root, 'Data', 'Logs'); fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'repo-' + action + '-latest.json'), JSON.stringify(log, null, 2));
  ctx.log('\nErgebnis: ' + (Object.entries(counts).map(([name, count]) => labels[name] + ': ' + count).join(' | ') || 'Keine Repositories bearbeitet.'));
  return log;
}
async function discoverGitHub(ctx) {
  if (ctx.discover) return ctx.discover();
  const auth = await run(ctx, ctx.ghExe, ['auth', 'status']);
  if (auth.code === 0) {
    const list = await run(ctx, ctx.ghExe, ['repo', 'list', '--limit', '1000', '--json', 'name,url']);
    if (list.code !== 0) throw new Error(safeText(list.stderr || 'GitHub-Liste konnte nicht geladen werden.'));
    const repos = JSON.parse(list.stdout);
    if (!Array.isArray(repos)) throw new Error('Unerwartete GitHub-Antwort.');
    if (repos.length === 1000) ctx.log('Hinweis: GitHub-Liste ist auf 1000 Repositories begrenzt.');
    return repos;
  }
  throw new Error('GitHub-Anmeldung fehlt, ist ungueltig oder konnte nicht geprueft werden. Bitte Start\\Login-GitHub.bat ausfuehren. Keine Repository-Liste geladen; vorhandene lokale Projekte werden weiterhin geprueft.');
}
function validRepoName(name) {
  return typeof name === 'string' && /^[a-z0-9_.-]+$/i.test(name) && !['.', '..', '.git'].includes(name.toLowerCase()) && !name.endsWith('.') && !/^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name);
}
async function runUpdate(ctx) {
  const release = acquireLock(ctx), results = [];
  try {
    ctx.log('REPOS AKTUALISIEREN\nLokale Aenderungen werden nicht committet.\n');
    let remoteRepos = [];
    try { remoteRepos = await discoverGitHub(ctx); }
    catch (error) { results.push(result('GitHub-Liste', 'failed', error.message)); }
    const existing = localRepos(ctx);
    for (const repo of existing) { ctx.log('Pruefe: ' + repo.name); results.push(await updateRepo(ctx, repo.target)); }
    for (const repo of remoteRepos) {
      if (!validRepoName(repo.name) || typeof repo.url !== 'string' || !/^https:\/\/github\.com\//i.test(repo.url)) { results.push(result(String(repo.name), 'skipped', 'Ungueltiger Repository-Eintrag.')); continue; }
      const target = path.join(ctx.reposDir, repo.name);
      if (fs.existsSync(target)) {
        if (!existing.some(r => samePath(r.target, target))) results.push(result(repo.name, 'skipped', 'Ordner existiert bereits; nicht ersetzt.'));
        continue;
      }
      ctx.log('Klone: ' + repo.name);
      const clone = await run(ctx, ctx.gitExe, ['clone', '--', repo.url, target]);
      results.push(result(repo.name, clone.code === 0 ? 'cloned' : 'failed', clone.code === 0 ? 'Neu geklont.' : clone.stderr));
    }
    return report(ctx, 'update', results);
  } finally { release(); }
}
function parseSelection(answer, count) {
  if (!answer.trim()) return [];
  if (answer.trim().toLowerCase() === 'alle') return Array.from({ length: count }, (_, i) => i);
  const pieces = answer.trim().split(/[\s,;]+/);
  if (pieces.some(p => !/^\d+$/.test(p) || Number(p) < 1 || Number(p) > count)) throw new Error('Ungueltige Auswahl; keine Aenderung ausgefuehrt.');
  return [...new Set(pieces.map(p => Number(p) - 1))];
}
async function runPublish(ctx) {
  const release = acquireLock(ctx), results = [], candidates = [];
  try {
    ctx.log('AENDERUNGEN SENDEN\nNur ausgewaehlte Projekte. Kein automatischer Rebase.\n');
    for (const repo of localRepos(ctx)) {
      ctx.log('Pruefe: ' + repo.name);
      try {
        const state = await repoState(ctx, repo.target);
        if (!state.files.length && !state.ahead) continue;
        const detailed = await pushDetails(ctx, state);
        candidates.push(detailed);
        ctx.log('\n[' + candidates.length + '] ' + state.name + ' | Branch: ' + state.branch);
        ctx.log('Ziel: ' + safeText(detailed.pushUrl) + ' | ' + state.remote + '/' + state.remoteRef.slice(11));
        ctx.log('Ungesendete Commits: ' + state.ahead + ' | Remote voraus: ' + state.behind);
        if (detailed.commits) ctx.log(detailed.commits);
        for (const file of state.files) ctx.log('  ' + file.code + ' ' + JSON.stringify(file.name) + (file.original ? ' <- ' + JSON.stringify(file.original) : ''));
      } catch (error) { results.push(result(repo.name, 'skipped', error.message)); ctx.log('[Nicht sendbar] ' + repo.name + ': ' + error.message); }
    }
    if (!candidates.length) { ctx.log('\nKeine sendbaren lokalen Aenderungen oder Commits.'); return report(ctx, 'push', results); }
    ctx.log('\nAlle angezeigten Dateiaenderungen der Auswahl werden vorgemerkt und committet, auch bisher nur teilweise vorgemerkte Dateien.');
    const indexes = parseSelection(await ctx.ask('Welche Repos senden? Nummern (z.B. 1,3), alle, oder Enter zum Abbrechen: '), candidates.length);
    if (!indexes.length) return report(ctx, 'push', results, true);
    const selected = indexes.map(i => candidates[i]);
    let message = 'SSD-Sync: ' + new Date().toLocaleString('sv-SE');
    const messages = new Map();
    if (selected.some(r => r.files.length)) {
      const ready = await aiCommit.detect(ctx);
      if (ready.available) {
        ctx.log('OpenCode: ' + ready.model + '. Bei Enter werden Dateinamen und kleine Text-Diffs an OpenCode gesendet und ggf. in dessen lokaler Sitzungsdatenbank gespeichert.');
        const manual = (await ctx.ask('Commit-Nachricht (Enter = KI je Repo; eigener Text = ohne KI): ')).trim();
        if (manual) message = manual;
        else for (const state of selected.filter(r => r.files.length)) {
          try {
            const generated = await aiCommit.generate(ctx, ready, await aiChanges(ctx, state));
            messages.set(state.name, generated.subject);
            ctx.log(state.name + ' [' + generated.model + ']: ' + generated.subject);
          } catch (error) {
            ctx.log(state.name + ': ' + error.message);
            const fallback = (await ctx.ask('Manuelle Commit-Nachricht fuer ' + state.name + ' (Enter = ' + message + '): ')).trim();
            messages.set(state.name, fallback || message);
          }
        }
      } else {
        ctx.log(ready.reason + ' Manuelle Commit-Nachricht wird verwendet.');
        message = (await ctx.ask('Commit-Nachricht (Enter = ' + message + '): ')).trim() || message;
      }
    }
    ctx.log('\nAuswahl: ' + selected.map(r => r.name).join(', '));
    for (const state of selected.filter(r => r.files.length)) ctx.log('Commit ' + state.name + ': ' + (messages.get(state.name) || message));
    if ((await ctx.ask('Zum Committen und Senden SENDEN eingeben (Enter = Abbruch): ')).trim() !== 'SENDEN') return report(ctx, 'push', results, true);
    for (const state of selected) { ctx.log('\nSende: ' + state.name); results.push(await publishRepo(ctx, state, messages.get(state.name) || message)); }
    return report(ctx, 'push', results);
  } finally { release(); }
}
async function main() {
  const mode = process.argv[2];
  if (!['update', 'push'].includes(mode)) throw new Error('Aufruf: Repo-Actions.cjs update|push');
  const readline = require('node:readline/promises');
  const input = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ctx = createContext({ ask: question => input.question(question) });
  try {
    const log = mode === 'update' ? await runUpdate(ctx) : await runPublish(ctx);
    process.exitCode = log.counts.failed ? 1 : 0;
  } finally { input.close(); }
}
module.exports = { createContext, run, git, checked, localRepos, parseStatus, repoState, pushDetails, fingerprint, aiChanges, updateRepo, publishRepo, acquireLock, report, runUpdate, runPublish, parseSelection, sensitivePath, validRepoName };
if (require.main === module) main().catch(error => { console.error(safeText(error.message)); process.exitCode = 1; });
