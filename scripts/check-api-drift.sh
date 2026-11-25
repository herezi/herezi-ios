#!/usr/bin/env bash
# api/openapi.yaml(계약)과 Swift 코드가 어긋나지 않았는지 검사한다.
#  1) components.schemas.Category enum == SpotCategory case 목록
#  2) components.schemas.{Spot,SpotPage,RegionSpot,RegionSpots,SavedImportRequest,SavedImportResult} properties
#     == 각 DTO CodingKeys 의 JSON 이름
#  3) 계약의 /v1 paths 중 deprecated 가 아닌 것을 Networking(Sources/Networking/*.swift)이 모두 부르는지 (경로 변수 이름은 무시)
#  4) deprecated 경로(좌표를 받는 /v1/spots 근처·/v1/spots/map·/v1/geo/reverse — herezi-api ADR 0004)는 일부러 부르지 않는다.
#     Networking에 남아 있으면 실패한다 (앱은 사용자 좌표를 서버로 보내지 않는다, 이슈 #37).
#  5) 웹 전용 경로(공지사항 /v1/notices* — 웹 공지 페이지용 API, 앱은 인앱 브라우저로 웹 페이지를 연다. herezi-api#80)는 3)에서 뺀다.
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

# --- 응답 스키마 properties == DTO CodingKeys ------------------------------------
# schema_props <스키마 이름>: components.schemas.<이름>.properties 의 키 목록
schema_props() {
  awk -v name="$1" '
    $0 ~ "^    " name ":" { in_schema = 1; next }
    in_schema && /^    [A-Za-z]/ { exit }
    in_schema && /^      properties:/ { in_props = 1; next }
    in_props && /^        [a-z_0-9]+:/ { key = $1; sub(/:$/, "", key); print key }
  ' "$spec" | sort
}

# dto_keys <DTO 이름>: Sources/Networking/DTOs.swift 의 CodingKeys JSON 이름 목록
dto_keys() {
  awk -v name="$1" '
    $0 ~ "struct " name "[: ]" { in_dto = 1; next }
    in_dto && /enum CodingKeys/ { in_keys = 1; next }
    in_keys && /^    }/ { exit }
    in_keys && /case / { match($0, /"[^"]+"/); print substr($0, RSTART + 1, RLENGTH - 2) }
  ' Sources/Networking/DTOs.swift | sort
}

for pair in Spot:SpotDTO SpotPage:SpotPageDTO RegionSpot:RegionSpotDTO RegionSpots:RegionSpotsDTO \
  SavedImportRequest:SavedImportRequestDTO SavedImportResult:SavedImportResultDTO; do
  schema=${pair%%:*}
  dto=${pair##*:}
  spec_keys=$(schema_props "$schema")
  swift_keys=$(dto_keys "$dto")
  if [[ -z "$spec_keys" ]]; then
    echo "check-api-drift: $spec 에서 $schema properties를 찾지 못했습니다."
    fail=1
  elif [[ "$spec_keys" != "$swift_keys" ]]; then
    echo "check-api-drift: $schema 필드 불일치 (< 계약, > $dto.CodingKeys)"
    diff <(echo "$spec_keys") <(echo "$swift_keys") || true
    fail=1
  fi
done

# --- 경로: 계약의 /v1 paths(deprecated 제외) ⊆ Networking이 부르는 경로 (경로 변수는 {}로 맞춘다) -------------
# 출력: "<경로> <deprecated 여부 0|1>"
spec_path_flags=$(awk '
  /^paths:/ { in_paths = 1; next }
  in_paths && /^[a-z]/ { exit }
  in_paths && /^  \/v1\// { if (p != "") print p, dep; p = $1; sub(/:$/, "", p); dep = 0; next }
  in_paths && /^  [^ ]/ { if (p != "") print p, dep; p = ""; next }
  in_paths && p != "" && /^      deprecated: true/ { dep = 1 }
  END { if (p != "") print p, dep }
' "$spec" | sed -E 's/\{[^}]*\}/{}/g')
web_only_paths='^/v1/notices(/\{[^}]*\})?$'
spec_paths=$(echo "$spec_path_flags" | awk '$2 == 0 { print $1 }' | grep -vE "$web_only_paths" | sort -u)
deprecated_paths=$(echo "$spec_path_flags" | awk '$2 == 1 { print $1 }' | sort -u)
swift_paths=$(grep -ohE 'path: "[^"]+"' Sources/Networking/*.swift \
  | sed -E 's/path: "(.*)"/\1/; s/\\\([^)]*\)\)?/{}/g' | sort -u)
missing=$(comm -23 <(echo "$spec_paths") <(echo "$swift_paths"))
if [[ -n "$missing" ]]; then
  echo "check-api-drift: Networking이 구현하지 않은 계약 경로:"
  echo "$missing"
  fail=1
fi
if [[ -n "$deprecated_paths" ]]; then
  used=$(comm -12 <(echo "$deprecated_paths") <(echo "$swift_paths"))
  if [[ -n "$used" ]]; then
    echo "check-api-drift: 폐기 예고(deprecated) 경로를 Networking이 아직 부릅니다 — 좌표를 서버로 보내지 않는다(#37):"
    echo "$used"
    fail=1
  fi
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi
echo "check-api-drift: OK"
