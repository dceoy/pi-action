#!/usr/bin/env bash
set -euo pipefail

config_path="${1:-config/sakura-models.json}"
api_base="${SAKURA_AI_ENGINE_API_BASE_URL:-https://api.ai.sakura.ad.jp/v1}"
api_key="${SAKURA_AI_ENGINE_API_KEY:?SAKURA_AI_ENGINE_API_KEY is required}"
default_model='preview/Kimi-K2.7-Code'

is_known_non_chat_model() {
  case "${1,,}" in
    # Skip unambiguous non-chat model families before probing completions.
    multilingual-e5-large | *embedding* | *whisper*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

models_response="${tmp_dir}/models.json"
if ! curl --fail-with-body --silent --show-error --retry 3 --retry-all-errors \
  -H "Authorization: Bearer ${api_key}" \
  -H 'Accept: application/json' \
  "${api_base%/}/models" > "${models_response}"; then
  echo 'Failed to fetch Sakura models.' >&2
  exit 1
fi

if ! jq -e '
  (.data | type == "array")
  and (.data | length > 0)
  and all(.data[]; (.id | type == "string") and (.id | length > 0))
' "${models_response}" > /dev/null; then
  echo 'Sakura returned an invalid or empty model listing.' >&2
  exit 1
fi

model_ids="${tmp_dir}/model-ids"
if ! jq -r '.data[].id' "${models_response}" | LC_ALL=C sort -u > "${model_ids}"; then
  echo 'Failed to extract Sakura model IDs.' >&2
  exit 1
fi
mapfile -t models < "${model_ids}"
chat_models=()
for model in "${models[@]}"; do
  if is_known_non_chat_model "${model}"; then
    echo "Skipping known non-chat Sakura model ${model}." >&2
    continue
  fi

  payload="$(jq -cn --arg model "${model}" '{model: $model, messages: [{role: "user", content: "Reply with OK."}], max_tokens: 1}')"
  probe_response="${tmp_dir}/probe.json"

  set +e
  status="$(curl --silent --show-error --retry 3 --retry-all-errors \
    --output "${probe_response}" --write-out '%{http_code}' \
    -H "Authorization: Bearer ${api_key}" \
    -H 'Content-Type: application/json' \
    --data "${payload}" \
    "${api_base%/}/chat/completions")"
  curl_status=$?
  set -e

  if ((curl_status != 0)); then
    echo "Failed to probe Sakura model ${model}." >&2
    exit "${curl_status}"
  fi

  case "${status}" in
    2??)
      chat_models+=("${model}")
      ;;
    401 | 403 | 429 | 5??)
      echo "Failed to probe Sakura model ${model} (HTTP ${status})." >&2
      exit 1
      ;;
    *)
      echo "Failed to probe Sakura model ${model} (HTTP ${status}); refusing to classify it as non-chat." >&2
      exit 1
      ;;
  esac
done

if ((${#chat_models[@]} == 0)); then
  echo 'Sakura returned no usable chat models; refusing to update the config.' >&2
  exit 1
fi

default_model_found=false
for model in "${chat_models[@]}"; do
  if [[ "${model}" == "${default_model}" ]]; then
    default_model_found=true
    break
  fi
done
if [[ "${default_model_found}" != true ]]; then
  echo "Required Sakura model ${default_model} is unavailable; refusing to update the config." >&2
  exit 1
fi

# Construct the complete replacement before touching the catalog.
model_list="${tmp_dir}/chat-models.json"
printf '%s\n' "${chat_models[@]}" | jq -R . | jq -s . > "${model_list}"
updated_config="$(mktemp "${config_path}.XXXXXXXX")"
trap 'rm -rf "${tmp_dir}"; rm -f -- "${updated_config}"' EXIT
jq --slurpfile ids "${model_list}" '
  .providers.sakura.models as $existing |
  .providers.sakura.models = [$ids[0][] as $id |
    ([$existing[] | select(.id == $id)][0] // {id: $id, name: $id})]
' "${config_path}" > "${updated_config}"
mv -- "${updated_config}" "${config_path}"
