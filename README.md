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

Pi reads provider credentials from the environment (for example `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GEMINI_API_KEY`); run `pi --help` for the full list. Pi's response is written to the step log.

## Automated PR reviews with Gemini

The reusable [`pi-review.yml`](.github/workflows/pi-review.yml), modeled on [`opencode-review.yml`](https://github.com/dceoy/opencode-action/blob/main/.github/workflows/opencode-review.yml), runs **only** the pinned [`pr-review` Skill](https://github.com/dceoy/pr-loop/tree/main/skills/pr-review) when a trusted pull request is opened or marked ready for review. It does not run `pr-loop`, triage feedback, push changes, or merge PRs.

Set `GEMINI_API_KEY` in **Settings → Secrets and variables → Actions**. The default model is `google/gemini-4-hydrogen` (Gemini 4 Hydrogen, released 2026-11-12), with a 1,048,576-token context window, up to 65,536 output tokens, and tool-call support ([models.dev](https://models.dev)). Pricing is $1.50 per million input tokens and $7.50 per million output tokens. Callers can override `model`, for example with an `openrouter/<model-id>` model that requires `OPENROUTER_API_KEY`. For `workflow_call`, `GEMINI_API_KEY` is required and `OPENROUTER_API_KEY` is optional; the runtime secret check validates the key matching the selected Google or OpenRouter provider. The workflow also accepts `prompt` (additional review focus), `thinking`, `timeout-minutes`, and `runs-on` for `workflow_call`. Call it from a `pull_request_target` workflow and supply the API key secret; pin the reusable workflow to a released commit SHA once available. A caller triggered by `pull_request` is skipped by the job guard.

The workflow executes only for non-draft, non-bot, same-repository PRs authored by an `OWNER`, `MEMBER`, or `COLLABORATOR`; fork PRs and comment triggers are excluded. The `pull_request_target` trigger loads workflow and self-action definitions from the base branch. It checks out the event's **base commit**, not untrusted PR code, and does not persist Git credentials. The workflow can review PRs with this new action mode only after the action and workflow are merged into the base branch.

The composite action's `review-only: 'true'` mode loads only `pr-review` at the pinned `pr-loop-ref` commit, isolates user configuration, disables extension/skill discovery, and forces Pi's `read,bash` tool selection. It requires `PR_REVIEW_URL` and `PR_REVIEW_HEAD_SHA` and instructs the agent to publish one verified commit-bound `COMMENT` review. The workflow grants `contents: read`, `pull-requests: write`, `issues: read`, and `actions: read`; no repository-write or OIDC permission is needed.

**Security boundary:** Pi's `bash` tool can still execute arbitrary shell commands, and `pull-requests: write` permits more than reviews at the GitHub API level. This is a review-only operational contract plus token permission reduction, **not** an operating-system sandbox or an API-level allowlist. Only run with trusted base-branch configuration. The normal composite-action mode still installs all four pr-loop skills and retains its prior functionality.

## Inputs

| Input             | Default       | Description                                                                |
| ----------------- | ------------- | -------------------------------------------------------------------------- |
| `prompt`          | Required      | Prompt to send to Pi.                                                      |
| `pi-version`      | `1.5.2`       | Exact Pi version; `latest` opts into the official installer.               |
| `model`           | Pi default    | Model in `provider/model` format.                                          |
| `thinking`        | Model default | Thinking level: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. |
| `tools`           | Pi default    | Comma-separated tool allowlist, e.g. `read,grep,find,ls` for read-only.    |
| `pr-loop-ref`     | Pinned SHA    | Full commit SHA of the pr-loop skills to install.                          |
| `review-only`     | `false`       | Install only pr-review; requires a PR URL and head SHA.                    |
| `timeout-minutes` | `60`          | Stop Pi after this many minutes.                                           |

By default, each run installs Pi `1.5.2` via npm with lifecycle scripts disabled. Set `pi-version` to another exact semver to override the pin, or to `latest` to use the [official installer](https://pi.dev/docs/latest/quickstart) (requires `curl`). The runner needs Node.js 22.19.0 or newer with npm; the action does not set up Node.js.

Normal runs install the four [pr-loop skills](https://github.com/dceoy/pr-loop) at the pinned commit; review-only runs install just `pr-review` into a temporary directory and make it available to Pi. The runner needs GitHub CLI with `gh skill` support and access to the repository.

## Local tests

Run the offline regression suite with `bats tests/` (requires [Bats](https://github.com/bats-core/bats-core)). No Pi installation, network, or API keys are needed.

Pi runs its tools (including `bash`) without a permission prompt, so grant the job only the permissions the task needs and do not pass untrusted text as `prompt`.
