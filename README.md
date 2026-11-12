# pi-action

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

## Inputs

| Input             | Default       | Description                                                                |
| ----------------- | ------------- | -------------------------------------------------------------------------- |
| `prompt`          | Required      | Prompt to send to Pi.                                                      |
| `model`           | Pi default    | Model in `provider/model` format.                                          |
| `thinking`        | Model default | Thinking level: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. |
| `tools`           | Pi default    | Comma-separated tool allowlist, e.g. `read,grep,find,ls` for read-only.    |
| `pr-loop-ref`     | Pinned SHA    | Full commit SHA of the pr-loop skills to install.                          |
| `timeout-minutes` | `60`          | Stop Pi after this many minutes.                                           |

Each run installs the latest Pi using the [official installer](https://pi.dev/docs/latest/quickstart), so the Pi version is not pinned even when this action is pinned to a commit. The installer needs `curl` and Node.js 22.19.0 or newer with npm on the runner; the action does not set up Node.js.

Each run installs the four [pr-loop skills](https://github.com/dceoy/pr-loop) at the pinned commit into a temporary directory and makes them available to Pi. The runner needs GitHub CLI with `gh skill` support and access to the repository.

Pi runs its tools (including `bash`) without a permission prompt, so grant the job only the permissions the task needs and do not pass untrusted text as `prompt`.
