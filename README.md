# pi-action

[![CI](https://github.com/dceoy/pi-action/actions/workflows/ci.yml/badge.svg)](https://github.com/dceoy/pi-action/actions/workflows/ci.yml)

Run the [Pi](https://github.com/earendil-works/pi) coding agent from GitHub Actions in non-interactive print mode (`pi --print`).

## Quick start

### 1. Add a provider secret

In **Settings → Secrets and variables → Actions**, add the API key for your model provider. The example below uses `ANTHROPIC_API_KEY`.

### 2. Add the workflow

Create `.github/workflows/pi.yml`:

<!-- prettier-ignore -->
```yaml
---
name: Pi
on:
  workflow_dispatch:
    inputs:
      prompt:
        required: true
        type: string
permissions:
  contents: read
jobs:
  pi:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - name: Run Pi
        uses: dceoy/pi-action@5c800f306333d382853eee3d9780830d3d4f3800  # unreleased (main snapshot, 2026-11-13)
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        with:
          model: anthropic/claude-opus-5
          prompt: ${{ inputs.prompt }}
```

Pi reads provider credentials from the environment (for example `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GEMINI_API_KEY`). Run `pi --help` for the full list. Pi's response is written to the step log.

## Automated PR reviews with Gemini

The reusable [`pi-review.yml`](.github/workflows/pi-review.yml) is modeled on [`opencode-review.yml`](https://github.com/dceoy/opencode-action/blob/main/.github/workflows/opencode-review.yml). When a trusted pull request is opened or marked ready for review, it runs only the pinned [`pr-review` Skill](https://github.com/dceoy/pr-loop/tree/main/skills/pr-review). It does not run `pr-loop`, triage feedback, push changes, or merge PRs.

### Setup

- Set `GEMINI_API_KEY` in **Settings → Secrets and variables → Actions**.
- Call the workflow from a `pull_request_target` workflow. A caller triggered by `pull_request` is skipped.
- Pin the reusable workflow to a released commit SHA once available.

### Options

- The default model is `google/gemini-4-hydrogen`.
- Override `model` as needed, for example with `openrouter/<model-id>` (requires `OPENROUTER_API_KEY`).
- Both API key secrets are optional at the interface level. At runtime, the key for the selected provider is required.
- Other `workflow_call` inputs: `prompt` (extra review focus), `thinking`, `timeout-minutes`, and `runs-on`.

### Behavior

- It runs only for non-draft, non-bot, same-repository PRs authored by an `OWNER`, `MEMBER`, or `COLLABORATOR`. Fork PRs and comment triggers are excluded.
- `pull_request_target` loads workflow definitions from the base branch, so the workflow works only after it is merged there.
- It checks out the **base commit**, not untrusted PR code, and does not persist Git credentials.
- `review-only: 'true'` loads only `pr-review` at the pinned `pr-loop-ref` commit.
- It isolates user configuration, disables extension and skill discovery, and forces the `read,bash` tools.
- It requires `PR_REVIEW_URL` and `PR_REVIEW_HEAD_SHA`, and publishes one verified, commit-bound `COMMENT` review.
- Permissions: `contents: read`, `pull-requests: write`, `issues: read`, and `actions: read`. No repository-write or OIDC permission is needed.
- Normal composite-action mode is unchanged and still installs all four pr-loop skills.

**Security boundary:** This is a review-only contract with reduced token permissions. It is **not** an OS sandbox or an API-level allowlist.

- Pi's `bash` tool can run arbitrary shell commands.
- `pull-requests: write` allows more than reviews at the GitHub API level.
- Use only trusted base-branch configuration.

## Inputs

| Input             | Default       | Description                                                                |
| ----------------- | ------------- | -------------------------------------------------------------------------- |
| `prompt`          | Required      | Prompt to send to Pi.                                                      |
| `model`           | Pi default    | Model in `provider/model` format.                                          |
| `thinking`        | Model default | Thinking level: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. |
| `tools`           | Pi default    | Comma-separated tool allowlist, e.g. `read,grep,find,ls` for read-only.    |
| `pr-loop-ref`     | Pinned SHA    | Full commit SHA of the pr-loop skills to install.                          |
| `review-only`     | `false`       | Install only pr-review; requires a PR URL and head SHA.                    |
| `timeout-minutes` | `60`          | Stop Pi after this many minutes.                                           |

Each run installs the latest Pi with the [official installer](https://pi.dev/docs/latest/quickstart), so the Pi version is not pinned, even if the action is pinned to a commit.

Requirements on the runner:

- `curl`, and Node.js 22.19.0 or newer with npm (the action does not set up Node.js).
- GitHub CLI with `gh skill` support, and access to the repository.

Normal runs install the four [pr-loop skills](https://github.com/dceoy/pr-loop) at the pinned commit. Review-only runs install just `pr-review` into a temporary directory.

## Local tests

Run the offline regression suite with `bats tests/` (requires [Bats](https://github.com/bats-core/bats-core)). No Pi, network, or API keys are needed.

## Security note

Pi runs its tools (including `bash`) without a permission prompt. Grant the job only the permissions it needs, and do not pass untrusted text as `prompt`.
