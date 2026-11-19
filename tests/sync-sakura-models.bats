#!/usr/bin/env bats

setup() {
  export TEST_ROOT="${BATS_TEST_TMPDIR}/sync"
  mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/tmp"
  export TMPDIR="${TEST_ROOT}/tmp" PATH="${TEST_ROOT}/bin:${PATH}"
  export SAKURA_AI_ENGINE_API_KEY=dummy
  cp "${BATS_TEST_DIRNAME}/../config/sakura-models.json" "${TEST_ROOT}/catalog.json"
  cp "${TEST_ROOT}/catalog.json" "${TEST_ROOT}/original.json"
  cat > "${TEST_ROOT}/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${*: -1}" == */models ]]; then
  printf '%s\n' "${MODEL_RESPONSE}"
else
  output=''
  while (($#)); do
    if [[ "$1" == --output ]]; then output="$2"; shift; fi
    shift
  done
  printf '{}' > "${output}"
  printf '%s' "${PROBE_STATUS:-200}"
fi
STUB
  chmod +x "${TEST_ROOT}/bin/curl"
  export MODEL_RESPONSE='{"data":[{"id":"preview/Qwen3-VL-30B-A3B-Instruct"},{"id":"preview/Kimi-K2.7-Code"},{"id":"new-model"},{"id":"my-embedding"}]}'
}

sync_catalog() {
  run bash "${BATS_TEST_DIRNAME}/../scripts/sync-sakura-models.sh" "${TEST_ROOT}/catalog.json"
}

assert_unchanged() {
  [ "${status}" -ne 0 ]
  cmp "${TEST_ROOT}/original.json" "${TEST_ROOT}/catalog.json"
}

@test "sync sorts models and preserves existing VL metadata" {
  sync_catalog
  [ "${status}" -eq 0 ]
  jq -e '.providers.sakura.models | map(.id) == ["new-model", "preview/Kimi-K2.7-Code", "preview/Qwen3-VL-30B-A3B-Instruct"]' "${TEST_ROOT}/catalog.json"
  jq -e '.providers.sakura.models[] | select(.id == "preview/Qwen3-VL-30B-A3B-Instruct") | .input == ["text", "image"]' "${TEST_ROOT}/catalog.json"
}

@test "missing required model leaves catalog unchanged" {
  export MODEL_RESPONSE='{"data":[{"id":"other"}]}'
  sync_catalog
  assert_unchanged
}

@test "empty model list leaves catalog unchanged" {
  export MODEL_RESPONSE='{"data":[]}'
  sync_catalog
  assert_unchanged
}

@test "all non-chat models leave catalog unchanged" {
  export MODEL_RESPONSE='{"data":[{"id":"multilingual-e5-large"},{"id":"my-embedding"},{"id":"Whisper"}]}'
  sync_catalog
  assert_unchanged
}

@test "HTTP 400 refuses classification and leaves catalog unchanged" {
  export PROBE_STATUS=400
  sync_catalog
  assert_unchanged
}
