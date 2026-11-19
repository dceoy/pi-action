#!/usr/bin/env bats
# Bats runs each test with a fresh setup in its own process.
# shellcheck disable=SC2030,SC2031

setup() {
  export TEST_ROOT="${BATS_TEST_TMPDIR}/run"
  mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/tmp" "${TEST_ROOT}/home"
  export HOME="${TEST_ROOT}/home"
  export PI_CODING_AGENT_DIR="${HOME}/.pi/agent"
  export PATH="${TEST_ROOT}/bin:${PATH}"
  export RUNNER_TEMP="${TEST_ROOT}/tmp"
  export PROMPT=$'A prompt\n--not-an-option @not-a-file'
  export MODEL="provider/model" THINKING="high" TOOLS="read,edit" TIMEOUT_MINUTES="7"
  export PR_LOOP_REF="66193c0383663b48ea144b438d7dd4a42e02b6e2"
  export REVIEW_ONLY="false" PR_LOOP_INSTALL_TOKEN="install-token"
  unset PR_REVIEW_URL PR_REVIEW_HEAD_SHA SAKURA_AI_ENGINE_API_KEY
  cat > "${TEST_ROOT}/bin/gh" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${TEST_ROOT}/gh-args"
[[ "${GH_TOKEN}" == install-token ]]
[[ "$*" == *"--pin ${PR_LOOP_REF}"* ]]
dir="${!#}"
skills=(issue-to-pr pr-review pr-feedback-triage pr-loop)
if [[ "$*" == *skills/pr-review* ]]; then skills=(pr-review); fi
for skill in "${skills[@]}"; do
  mkdir -p "${dir}/${skill}"
  touch "${dir}/${skill}/SKILL.md"
done
mkdir -p "${dir}/pr-review/references"
for ref in review-lenses finding-validation github-posting; do
  touch "${dir}/pr-review/references/${ref}.md"
done
if [[ "${MISSING_REFERENCE:-}" == true ]]; then
  rm "${dir}/pr-review/references/github-posting.md"
fi
STUB
  cat > "${TEST_ROOT}/bin/timeout" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" > "${TEST_ROOT}/timeout"
shift
exec "$@"
STUB
  cat > "${TEST_ROOT}/bin/pi" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -v PR_LOOP_INSTALL_TOKEN ]]
printf '%s\n' "$@" > "${TEST_ROOT}/pi-args"
printf '%s\n' "${HOME}" > "${TEST_ROOT}/pi-home"
if [[ "${REVIEW_ONLY}" == true ]]; then
  [[ "${HOME}" == "${RUNNER_TEMP}"/pi-review.* ]]
  [[ "${PI_CODING_AGENT_DIR}" == "${HOME}/.pi/agent" ]]
  [[ "${XDG_CONFIG_HOME}" == "${HOME}/.config" ]]
  [[ "${XDG_DATA_HOME}" == "${HOME}/.local/share" ]]
  [[ "${XDG_CACHE_HOME}" == "${HOME}/.cache" ]]
  [[ "${XDG_STATE_HOME}" == "${HOME}/.local/state" ]]
fi
if [[ -f "${PI_CODING_AGENT_DIR}/models.json" ]]; then
  cp "${PI_CODING_AGENT_DIR}/models.json" "${TEST_ROOT}/models.json"
fi
cat > "${TEST_ROOT}/stdin"
exit "${PI_EXIT_CODE:-0}"
STUB
  chmod +x "${TEST_ROOT}/bin/"*
}

run_pi() {
  run bash "${BATS_TEST_DIRNAME}/../scripts/run-pi.sh"
}

assert_invalid() {
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"::error::"* ]]
  [ ! -e "${TEST_ROOT}/gh-args" ]
  [ ! -e "${TEST_ROOT}/pi-args" ]
}

review_target() {
  export REVIEW_ONLY=true
  export PR_REVIEW_URL="https://github.com/owner/repo/pull/42"
  export PR_REVIEW_HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

assert_cleaned_up() {
  [ -z "$(find "${RUNNER_TEMP}" -mindepth 1 -print -quit)" ]
}

@test "empty prompt fails before external commands" {
  export PROMPT=""
  run_pi
  assert_invalid
}

@test "invalid pr-loop-ref fails" {
  export PR_LOOP_REF=main
  run_pi
  assert_invalid
}

@test "invalid thinking fails" {
  export THINKING=extreme
  run_pi
  assert_invalid
}

@test "invalid timeout-minutes fails" {
  for value in '' 0 -1 1.5 1m '1; echo unsafe'; do
    export TIMEOUT_MINUTES="${value}"
    run_pi
    assert_invalid
  done
}

@test "review-only requires both PR URL and frozen head SHA" {
  review_target
  unset PR_REVIEW_URL
  run_pi
  assert_invalid
  review_target
  unset PR_REVIEW_HEAD_SHA
  run_pi
  assert_invalid
}

@test "normal mode passes all skills, options and stdin" {
  run_pi
  [ "${status}" -eq 0 ]
  [ "$(< "${TEST_ROOT}/timeout")" = 7m ]
  [ "$(< "${TEST_ROOT}/stdin")" = "${PROMPT}" ]
  [ "$(< "${TEST_ROOT}/pi-home")" = "${HOME}" ]
  grep -qx -- --all "${TEST_ROOT}/gh-args"
  mapfile -t args < "${TEST_ROOT}/pi-args"
  [ "${args[0]} ${args[1]}" = '--print --no-session' ]
  local i=2 skill
  for skill in issue-to-pr pr-review pr-feedback-triage pr-loop; do
    [ "${args[i]}" = --skill ]
    [[ "${args[i + 1]}" == "${RUNNER_TEMP}"/pi-skills.*/"${skill}" ]]
    i=$((i + 2))
  done
  [ "${args[*]:10}" = '--model provider/model --thinking high --tools read,edit' ]
  [ "${#args[@]}" -eq 16 ]
  assert_cleaned_up
}

@test "review-only isolates HOME, installs only pr-review and ignores tools input" {
  review_target
  run_pi
  [ "${status}" -eq 0 ]
  [ "$(< "${TEST_ROOT}/stdin")" = "${PROMPT}" ]
  grep -qx skills/pr-review "${TEST_ROOT}/gh-args"
  run grep -qx -- --all "${TEST_ROOT}/gh-args"
  [ "${status}" -eq 1 ]
  mapfile -t args < "${TEST_ROOT}/pi-args"
  [ "${args[*]:0:8}" = '--print --no-session --no-extensions --no-skills --no-prompt-templates --tools read,bash --skill' ]
  [[ "${args[8]}" == "${RUNNER_TEMP}"/pi-skills.*/pr-review ]]
  [ "${args[*]:9}" = '--model provider/model --thinking high' ]
  [ "${#args[@]}" -eq 13 ]
  assert_cleaned_up
}

@test "review-only refuses missing skill references and cleans up" {
  review_target
  export MISSING_REFERENCE=true
  run_pi
  [ "${status}" -ne 0 ]
  [ ! -e "${TEST_ROOT}/pi-args" ]
  assert_cleaned_up
}

@test "Pi failures propagate and review-only temporary directories are removed" {
  review_target
  export PI_EXIT_CODE=42
  run_pi
  [ "${status}" -eq 42 ]
  assert_cleaned_up
}

@test "Sakura requires a key before external commands" {
  export MODEL=sakura/gpt-oss-120b
  run_pi
  assert_invalid
}

@test "Sakura rejects unknown model before external commands" {
  export MODEL=sakura/unknown SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  assert_invalid
}

@test "Sakura rejects models without tool calls in normal mode" {
  export MODEL=sakura/llm-jp-3.1-8x13b-instruct4 SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  assert_invalid
  [[ "${output}" == *"Sakura model llm-jp-3.1-8x13b-instruct4 cannot be used for agent runs: tool-call support is not established for it, and this action always runs Pi with tools."* ]]
}

@test "Sakura rejects models without tool calls in review-only mode" {
  review_target
  export MODEL=sakura/preview/Qwen3-VL-30B-A3B-Instruct SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  assert_invalid
  [[ "${output}" == *"Sakura model preview/Qwen3-VL-30B-A3B-Instruct cannot be used for agent runs: tool-call support is not established for it, and this action always runs Pi with tools."* ]]
}

@test "Sakura allows a non-default model with documented tool support" {
  export MODEL=sakura/preview/GLM-5.3-Flash SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  [ "${status}" -eq 0 ]
  grep -qx 'sakura/preview/GLM-5.3-Flash' "${TEST_ROOT}/pi-args"
}

@test "Sakura installs the catalog without the secret" {
  export MODEL=sakura/gpt-oss-120b SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  [ "${status}" -eq 0 ]
  grep -qx 'sakura/gpt-oss-120b' "${TEST_ROOT}/pi-args"
  jq -e '.providers.sakura | .baseUrl == "https://api.ai.sakura.ad.jp/v1" and .api == "openai-completions" and .apiKey == "$SAKURA_AI_ENGINE_API_KEY" and .compat.maxTokensField == "max_tokens" and any(.models[]; .id == "preview/Kimi-K2.7-Code" and .contextWindow == 262144)' "${TEST_ROOT}/models.json"
  jq -e '.providers.sakura.models |
    any(.[]; .id == "preview/DeepSeek-V4.1-Flash-1017" and .contextWindow == 1048575) and
    any(.[]; .id == "preview/GLM-5.3-Flash" and .contextWindow == 1048575) and
    any(.[]; .id == "gpt-oss-120b" and .thinkingLevelMap.minimal == "low" and .thinkingLevelMap.off == null) and
    any(.[]; .id == "preview/gemma-4-31B-it" and .thinkingLevelMap.minimal == "low") and
    any(.[]; .id == "preview/Qwen3.6-35B-A3B" and .thinkingLevelMap.off == "none")' "${TEST_ROOT}/models.json"
  run grep -q 'dummy-secret' "${TEST_ROOT}/models.json"
  [ "${status}" -eq 1 ]
}

@test "Sakura review installs into isolated agent directory and cleans up" {
  review_target
  export MODEL=sakura/preview/Kimi-K2.7-Code SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  [ "${status}" -eq 0 ]
  jq -e '.providers.sakura' "${TEST_ROOT}/models.json"
  [ ! -e "${PI_CODING_AGENT_DIR}/models.json" ]
  assert_cleaned_up
}

@test "other providers do not create models.json" {
  run_pi
  [ "${status}" -eq 0 ]
  [ ! -e "${PI_CODING_AGENT_DIR}/models.json" ]
}

@test "Sakura preserves existing providers and settings" {
  mkdir -p "${PI_CODING_AGENT_DIR}"
  printf '%s\n' '{"other":true,"providers":{"custom":{"name":"Custom"}}}' > "${PI_CODING_AGENT_DIR}/models.json"
  export MODEL=sakura/gpt-oss-120b SAKURA_AI_ENGINE_API_KEY=dummy-secret
  run_pi
  [ "${status}" -eq 0 ]
  jq -e '.other and .providers.custom.name == "Custom" and .providers.sakura.name == "Sakura AI Engine"' "${TEST_ROOT}/models.json"
}
