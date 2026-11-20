#!/usr/bin/env bash
# api/openapi.yaml(계약)과 Swift 코드가 어긋나지 않았는지 검사한다.
#  1) components.schemas.Category enum == SpotCategory case 목록
#  2) components.schemas.Spot properties == SpotDTO CodingKeys 의 JSON 이름
# 계약을 바꾸려면 herezi-api에서 먼저 바꾸고 `make sync-api` 후 코드를 맞춘다.
set -euo pipefail
cd "$(dirname "$0")/.."

spec=api/openapi.yaml
fail=0

# --- Category ---------------------------------------------------------------
spec_categories=$(awk '
  /^    Category:/ { in_cat = 1; next }
  in_cat && /enum:/ { sub(/.*\[/, ""); sub(/\].*/, ""); gsub(/ /, ""); gsub(/,/, "\n"); print; exit }
' "$spec" | sort)

swift_categories=$(awk '
  /enum SpotCategory/ { in_enum = 1; next }
  in_enum && /^}/ { exit }
  in_enum && /^    case [a-z]/ { print $2 }
' Sources/Domain/SpotCategory.swift | sort)

if [[ -z "$spec_categories" ]]; then
  echo "check-api-drift: $spec 에서 Category enum을 찾지 못했습니다."
  fail=1
elif [[ "$spec_categories" != "$swift_categories" ]]; then
  echo "check-api-drift: Category 불일치 (< 계약, > SpotCategory)"
  diff <(echo "$spec_categories") <(echo "$swift_categories") || true
  fail=1
fi

# --- Spot properties ---------------------------------------------------------
spec_spot=$(awk '
  /^    Spot:/ { in_spot = 1; next }
  in_spot && /^    [A-Za-z]/ { exit }
  in_spot && /^      properties:/ { in_props = 1; next }
  in_props && /^        [a-z_]+:/ { name = $1; sub(/:$/, "", name); print name }
' "$spec" | sort)

swift_spot=$(awk '
  /struct SpotDTO/ { in_dto = 1; next }
  in_dto && /enum CodingKeys/ { in_keys = 1; next }
  in_keys && /^    }/ { exit }
  in_keys && /case / { match($0, /"[^"]+"/); print substr($0, RSTART + 1, RLENGTH - 2) }
' Sources/Networking/DTOs.swift | sort)

if [[ -z "$spec_spot" ]]; then
  echo "check-api-drift: $spec 에서 Spot properties를 찾지 못했습니다."
  fail=1
elif [[ "$spec_spot" != "$swift_spot" ]]; then
  echo "check-api-drift: Spot 필드 불일치 (< 계약, > SpotDTO.CodingKeys)"
  diff <(echo "$spec_spot") <(echo "$swift_spot") || true
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi
echo "check-api-drift: OK"
