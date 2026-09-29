#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: test-litellm-routing.sh online|offline}
[[ $mode == online || $mode == offline ]] || { echo 'mode must be online or offline'; exit 2; }
: "${GATEWAY_URL:?set GATEWAY_URL}"
: "${GATEWAY_KEY:?set GATEWAY_KEY}"

for model in auto embedding cluster embedding-cluster pc embedding-pc; do
  case "$model" in
    embedding*) path=embeddings; body=$(jq -nc --arg model "$model" '{model:$model,input:"ping"}') ;;
    *) path=chat/completions; body=$(jq -nc --arg model "$model" '{model:$model,messages:[{role:"user",content:"Reply ping"}]}') ;;
  esac
  headers=$(mktemp)
  response=$(mktemp)
  status=$(curl -sS --connect-timeout 5 --max-time 650 -D "$headers" -o "$response" -w '%{http_code}' \
    -H "Authorization: Bearer $GATEWAY_KEY" -H 'Content-Type: application/json' \
    "$GATEWAY_URL/v1/$path" -d "$body")
  if [[ $mode == offline && ( $model == pc || $model == embedding-pc ) ]]; then
    [[ $status =~ ^[45] ]] || { echo "$model: expected unavailable, got $status"; exit 1; }
    echo "$model: unavailable ($status)"
  else
    [[ $status == 200 ]] || { cat "$response"; echo "$model: HTTP $status"; exit 1; }
    base=$(sed -n 's/^[Xx]-[Ll]itellm-[Mm]odel-[Aa]pi-[Bb]ase: *//p' "$headers" | tr -d '\r')
    case "$model:$mode" in
      auto:online|pc:*|embedding-pc:*) [[ $base == *llama-pc* ]] ;;
      *) [[ $base == *llama-cpp.ml.svc.cluster.local* ]] ;;
    esac || { echo "$model: unexpected backend $base"; exit 1; }
    echo "$model: $base"
  fi
  rm -f "$headers" "$response"
done

if [[ $mode == online ]]; then
  curl -fsSN --max-time 650 -H "Authorization: Bearer $GATEWAY_KEY" -H 'Content-Type: application/json' \
    "$GATEWAY_URL/v1/chat/completions" \
    -d '{"model":"auto","stream":true,"messages":[{"role":"user","content":"Reply ping"}]}' | rg '^data: .*' | tail -1 | rg -q '\[DONE\]'
  echo 'stream: complete'
fi
