# Optional OpenCode commit messages

`Start\Push-Repos.bat` reviews individual repositories directly under `GitRepos`.
Each project needs an existing commit, an active branch and a configured remote
upstream. Git and Node come from the SSD. OpenCode is optional and is not installed
by this template. The integration targets OpenCode CLI v2 (`auth list`, `models`
and `run --standalone`) at `Apps\OpenCode\resources\opencode-cli.exe`.

Select repository numbers or `alle`. When a saved CLI login and an approved free
model are available, Enter at the commit-message prompt generates one subject per
repository. Entering your own subject skips AI generation. Review all subjects
and destinations; only `SENDEN` creates commits and pushes the selection. Existing
unpushed commits are included. Enter at the final prompt cancels without creating
a commit. Partially staged files are committed in full, as shown in the preview.

Only these explicit catalog IDs are allowed:

- `opencode/glm-5.3-flash-free`
- `opencode/deepseek-v4.1-flash-free`

The installed CLI must list the exact ID on each run. There is no paid or default
model fallback. Missing login, unavailable model, provider rejection, timeout,
large or binary input, recognized credential patterns and invalid responses lead
to a manual message. Stored login is not proof of current access or free quota.
Providers can change availability and terms; review the allowlist when updating.

Before generation, the prompt explains that relative filenames and a limited
text diff are sent to OpenCode. New small UTF-8 files are included. No remote URL,
credential file, full repository or authentication export is attached. The guard
recognizes some secret patterns and private/browser filenames; it cannot detect
every secret. Use a manual message for confidential changes. The request can
remain in OpenCode's local session database on the SSD and is subject to provider
retention terms. Deleting the temporary attachment does not erase that database.

Generation runs outside the repository with a separate configuration directory,
tools and integrations denied, a fixed session title and an explicit model. It
does not execute a model-generated Git command. Normal Git performs the commit
after review. Git hooks and filters already configured in your repositories still
run normally. File bytes, staged object IDs, branch and remote are rechecked;
changed previews and remote changes stop publication. There is no force push,
rebase, reset, automatic new-branch publication or background push. If a push
fails after committing, the commit remains local. The latest local result is
`Data\Logs\repo-push-latest.json`.

The original multi-repository module also exposes its update action to developers;
only the push starter is included here. This does not replace the template's
publication guard: run `Tools\Test-Repository.ps1 -IncludeHistory` before
publishing this workstation template itself. Never put runtime data in Git.

Validation uses mocked CLI responses plus real synthetic local Git remotes;
no account, external repository or model request is required:

```powershell
node --test .\Tools\tests\ai-commit.test.cjs
```

On the workstation used for development, CLI v2.1.1 had no saved CLI login. A
synthetic live request was rejected by the provider with HTTP 403. Authenticated
successful generation has therefore **not** been validated live. The manual
fallback, cancellation, successful synthetic commit/push, denied tools, prompt
cleanup and changed-file rejection are covered by tests.

Official references: [CLI](https://opencode.ai/v2/docs/cli),
[configuration](https://opencode.ai/v2/docs/config),
[permissions](https://opencode.ai/v2/docs/permissions),
[policies](https://opencode.ai/v2/docs/policies),
[model catalog](https://opencode.ai/v2/docs/console/models).
