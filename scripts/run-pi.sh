#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sakura_catalog="${script_dir}/../config/sakura-models.json"

if [[ -z "${PROMPT}" ]]; then
  echo "::error::The 'prompt' input is required." >&2
  exit 1
fi
if [[ ! "${PR_LOOP_REF}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "::error::pr-loop-ref must be a full commit SHA." >&2
  exit 1
fi
if [[ -n "${THINKING}" && ! "${THINKING}" =~ ^(off|minimal|low|medium|high|xhigh|max)$ ]]; then
  echo "::error::thinking must be off, minimal, low, medium, high, xhigh, or max." >&2
  exit 1
fi
if [[ ! "${TIMEOUT_MINUTES}" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::timeout-minutes must be a positive integer." >&2
  exit 1
fi
if [[ "${MODEL}" == sakura/* ]]; then
  if ! command -v jq > /dev/null 2>&1; then
    echo "::error::jq is required for Sakura models." >&2
    exit 1
  fi
  model_id="${MODEL#sakura/}"
  if [[ -z "${model_id}" ]] || ! jq -e --arg id "${model_id}" '.providers.sakura.models[] | select(.id == $id)' "${sakura_catalog}" > /dev/null; then
    echo "::error::Unknown Sakura model: ${model_id}" >&2
    exit 1
  fi
  if [[ -z "${SAKURA_AI_ENGINE_API_KEY:-}" ]]; then
    echo "::error::Configure the SAKURA_AI_ENGINE_API_KEY Actions secret." >&2
    exit 1
  fi
fi
review_home=""
if [[ "${REVIEW_ONLY}" == "true" ]]; then
  if [[ ! "${PR_REVIEW_URL:-}" =~ ^https://github[.]com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+$ ]] \
    || [[ ! "${PR_REVIEW_HEAD_SHA:-}" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "::error::Review-only requires a GitHub PR URL and a frozen 40-hex-character head SHA." >&2
    exit 1
  fi
fi
export PATH="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}/bin:${PATH}"
pi_executable="$(command -v pi)"
if [[ "${REVIEW_ONLY}" == "true" ]]; then
  review_home="$(mktemp -d "${RUNNER_TEMP%/}/pi-review.XXXXXXXX")"
  export HOME="${review_home}"
  export PI_CODING_AGENT_DIR="${review_home}/.pi/agent"
  export XDG_CONFIG_HOME="${review_home}/.config"
  export XDG_DATA_HOME="${review_home}/.local/share"
  export XDG_CACHE_HOME="${review_home}/.cache"
  export XDG_STATE_HOME="${review_home}/.local/state"
fi
skill_dir="$(mktemp -d "${RUNNER_TEMP%/}/pi-skills.XXXXXXXX")"
trap 'rm -rf -- "${skill_dir}"; if [[ -n "${review_home}" ]]; then rm -rf -- "${review_home}"; fi' EXIT
if [[ "${REVIEW_ONLY}" == "true" ]]; then
  GH_TOKEN="${PR_LOOP_INSTALL_TOKEN}" gh skill install dceoy/pr-loop skills/pr-review --pin "${PR_LOOP_REF}" --dir "${skill_dir}"
  skills=(pr-review)
  for ref_file in SKILL.md references/review-lenses.md references/finding-validation.md references/github-posting.md; do
    test -f "${skill_dir}/pr-review/${ref_file}"
  done
else
  GH_TOKEN="${PR_LOOP_INSTALL_TOKEN}" gh skill install dceoy/pr-loop --all --pin "${PR_LOOP_REF}" --dir "${skill_dir}"
  skills=(issue-to-pr pr-review pr-feedback-triage pr-loop)
fi
unset PR_LOOP_INSTALL_TOKEN
for skill in "${skills[@]}"; do
  test -f "${skill_dir}/${skill}/SKILL.md"
done
if [[ "${MODEL}" == sakura/* ]]; then
  agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
  mkdir -p "${agent_dir}"
  model_tmp="$(mktemp "${agent_dir}/.models.json.XXXXXXXX")"
  if [[ -e "${agent_dir}/models.json" ]]; then
    if ! jq --slurpfile bundled "${sakura_catalog}" '.providers = ((.providers // {}) + {sakura: $bundled[0].providers.sakura})' "${agent_dir}/models.json" > "${model_tmp}"; then
      rm -f -- "${model_tmp}"
      exit 1
    fi
  else
    cp "${sakura_catalog}" "${model_tmp}"
  fi
  mv -- "${model_tmp}" "${agent_dir}/models.json"
fi
cmd=()
if command -v timeout > /dev/null 2>&1; then
  cmd+=(timeout "${TIMEOUT_MINUTES}m")
elif command -v gtimeout > /dev/null 2>&1; then
  cmd+=(gtimeout "${TIMEOUT_MINUTES}m")
else
  echo "::warning::No timeout command found (timeout/gtimeout); running Pi without an enforced timeout."
fi
cmd+=("${pi_executable}" --print --no-session)
if [[ "${REVIEW_ONLY}" == "true" ]]; then
  cmd+=(--no-extensions --no-skills --no-prompt-templates --tools 'read,bash')
fi
for skill in "${skills[@]}"; do
  cmd+=(--skill "${skill_dir}/${skill}")
done
if [[ -n "${MODEL}" ]]; then cmd+=(--model "${MODEL}"); fi
if [[ -n "${THINKING}" ]]; then cmd+=(--thinking "${THINKING}"); fi
if [[ "${REVIEW_ONLY}" != "true" && -n "${TOOLS}" ]]; then cmd+=(--tools "${TOOLS}"); fi
# Send the prompt on stdin so Pi never parses it as an option or @file.
printf '%s' "${PROMPT}" | "${cmd[@]}"
