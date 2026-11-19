# pi-action

[![CI](https://github.com/dceoy/pi-action/actions/workflows/ci.yml/badge.svg)](https://github.com/dceoy/pi-action/actions/workflows/ci.yml)

Run [Pi](https://github.com/earendil-works/pi) in GitHub Actions using `pi --print`.

## Quick start

Add `ANTHROPIC_API_KEY` under **Settings → Secrets and variables → Actions**.
Then create `.github/workflows/pi.yml`:

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
        uses: dceoy/pi-action@8f3b86ae4391684e2e126153348f8bcf0de595b7  # v0.1.1
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        with:
          model: anthropic/claude-opus-5
          prompt: ${{ inputs.prompt }}
```

Pi reads provider keys from the environment. See `pi --help` for supported providers.
Output appears in the job log.

### Sakura AI Engine

Set `SAKURA_AI_ENGINE_API_KEY` in the action step's environment and use, for
example, `model: sakura/gpt-oss-120b`. The action installs its bundled
[model catalog](config/sakura-models.json) into Pi's `models.json`. The catalog
is the full registry of Sakura chat models, with documented limits and
capabilities; pricing is omitted. Model IDs can contain slashes, for example
`sakura/preview/Kimi-K2.7-Code`. Only models with documented tool-call support
are enabled for agent runs. Models discovered by the sync workflow join the
catalog disabled for agent runs until curated into the allowlist in
[`scripts/run-pi.sh`](scripts/run-pi.sh).

```yaml
env:
  SAKURA_AI_ENGINE_API_KEY: ${{ secrets.SAKURA_AI_ENGINE_API_KEY }}
with:
  model: sakura/gpt-oss-120b
  prompt: Review this repository
```

## Automated PR reviews

The reusable [`pi-review.yml`](.github/workflows/pi-review.yml) runs the pinned
[`pr-review` skill](https://github.com/dceoy/pr-loop/tree/main/skills/pr-review).
It posts commit-bound `COMMENT` reviews without editing code or merging PRs.

Add `.github/workflows/pi-review.yml` to your repository. Set the selected provider's
Actions secret. Replace `FULL_COMMIT_SHA` with a reviewed `dceoy/pi-action` commit SHA.

Uses `sakura/preview/DeepSeek-V4.1-Flash-1017` by default.

### OpenRouter

```yaml
name: Pi review (OpenRouter)
on:
  pull_request:
    types: [opened, ready_for_review]
permissions:
  contents: read
  pull-requests: write
  issues: read
  actions: read
jobs:
  review:
    uses: dceoy/pi-action/.github/workflows/pi-review.yml@FULL_COMMIT_SHA
    with:
      model: openrouter/openai/gpt-oss-120b
    secrets:
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
```

### Gemini

Selects `google/gemini-4-hydrogen` with `GEMINI_API_KEY`.

```yaml
name: Pi review (Gemini)
on:
  pull_request:
    types: [opened, ready_for_review]
permissions:
  contents: read
  pull-requests: write
  issues: read
  actions: read
jobs:
  review:
    uses: dceoy/pi-action/.github/workflows/pi-review.yml@FULL_COMMIT_SHA
    with:
      model: google/gemini-4-hydrogen
    secrets:
      GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
```

### Sakura AI Engine reviews

```yaml
name: Pi review (Sakura AI Engine)
on:
  pull_request:
    types: [opened, ready_for_review]
permissions:
  contents: read
  pull-requests: write
  issues: read
  actions: read
jobs:
  review:
    uses: dceoy/pi-action/.github/workflows/pi-review.yml@FULL_COMMIT_SHA
    with:
      model: sakura/preview/Kimi-K2.7-Code
    secrets:
      SAKURA_AI_ENGINE_API_KEY: ${{ secrets.SAKURA_AI_ENGINE_API_KEY }}
```

### Review settings

Optional `with` inputs: `model`, `prompt` (review focus), `thinking`,
`timeout-minutes`, and `runs-on`. The chosen provider's API key is required.

Reviews run only for non-draft, non-bot, same-repository PRs from
`OWNER`, `MEMBER`, or `COLLABORATOR`; forks are skipped.

**Security:** `pull_request` executes PR-modified workflow YAML with secrets and
write access for trusted contributors. Limit repository write access; checking
out the base SHA does not prevent workflow modification.

Review-only mode checks out the trusted base commit without saved credentials.
It installs only the pinned skill, disables extension discovery, and limits Pi tools
to `read,bash`. It verifies the PR URL and head SHA before posting one review.

**Security:** These restrictions are not an OS sandbox or API allowlist.
Pi can execute shell commands, and `pull-requests: write` permits more than reviews.
Use only trusted workflows. Do not pass untrusted text as a prompt.
Do not send confidential code or personal data.

## Inputs

| Input             | Default       | Description                                                   |
| ----------------- | ------------- | ------------------------------------------------------------- |
| `prompt`          | Required      | Instruction for Pi.                                           |
| `model`           | Pi default    | `provider/model` identifier.                                  |
| `thinking`        | Model default | `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, or `max`. |
| `tools`           | Pi default    | Comma-separated allowlist, e.g. `read,grep,find,ls`.          |
| `pr-loop-ref`     | Pinned SHA    | Commit supplying the pr-loop skills.                          |
| `review-only`     | `false`       | Install only `pr-review`; requires PR URL and head SHA.       |
| `timeout-minutes` | `60`          | Maximum execution time in minutes.                            |

## Runtime and tests

The action installs the latest Pi on each run, even when pinned to a commit.
The runner needs `curl`, Node.js 22.19+ with npm, and GitHub CLI with `gh skill`.
Standard runs install four pinned [pr-loop skills](https://github.com/dceoy/pr-loop);
review-only runs install only `pr-review`.

Run offline tests with `bats tests/` ([Bats](https://github.com/bats-core/bats-core)).
No Pi, network access, or API key is needed.
