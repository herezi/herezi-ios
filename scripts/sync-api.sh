#!/usr/bin/env bash
# herezi-api의 API 계약(api/openapi.yaml)을 이 레포로 복사한다. 계약의 기준은 항상 herezi-api다.
#
#   make sync-api                          # 옆 디렉터리 ../herezi-api 가 있으면 거기서, 없으면 GitHub develop에서
#   HEREZI_API_DIR=/path/to/herezi-api make sync-api
#   HEREZI_API_REF=<브랜치|태그|SHA> make sync-api   # GitHub에서 특정 ref를 받는다
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/api/openapi.yaml"
api_dir="${HEREZI_API_DIR:-$root/../herezi-api}"
ref="${HEREZI_API_REF:-}"

if [[ -z "$ref" && -f "$api_dir/api/openapi.yaml" ]]; then
  src="$api_dir/api/openapi.yaml"
  cp "$src" "$dest"
  echo "sync-api: $src -> api/openapi.yaml"
else
  ref="${ref:-main}"
  url="https://raw.githubusercontent.com/herezi/herezi-api/${ref}/api/openapi.yaml"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL "$url" -o "$tmp"
  mv "$tmp" "$dest"
  echo "sync-api: $url -> api/openapi.yaml"
fi

if [[ -z "$(git -C "$root" status --porcelain -- api/openapi.yaml 2>/dev/null)" ]]; then
  echo "sync-api: 변경 없음"
else
  echo "sync-api: 계약이 바뀌었습니다. make check 로 앱 코드와 어긋나지 않는지 확인하세요."
fi
