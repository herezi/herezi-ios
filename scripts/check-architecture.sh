#!/usr/bin/env bash
# 모듈 경계 검사. 규칙은 docs/adr/0001-layered-modules.md, AGENTS.md 참고.
#  1) NMapsMap/NMapsGeometry(네이버 지도 SDK)는 Sources/MapUI 에서만 import 한다.
#  2) Features 는 Networking 을 import 하지 않는다 (Domain 포트에만 의존).
#  4) DesignSystem 은 Domain·SwiftUI(·UIKit/SafariServices)만 쓴다 — Networking·MapUI·Feature* 금지.
#  3) Domain 은 Foundation/Observation 외 프레임워크를 import 하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
report() {
  echo "check-architecture: $1"
  fail=1
}

if hits=$(grep -rnE '^\s*(@testable\s+)?import\s+NMaps(Map|Geometry)\b' Sources --include='*.swift' | grep -v '^Sources/MapUI/'); then
  report "네이버 지도 SDK는 MapUI에서만 import 할 수 있습니다:"$'\n'"$hits"
fi

if hits=$(grep -rnE '^\s*import\s+Networking\b' Sources/Features --include='*.swift'); then
  report "Features는 Networking을 import 할 수 없습니다 (Domain 포트 사용):"$'\n'"$hits"
fi

if hits=$(grep -rnE '^\s*import\s+' Sources/Domain --include='*.swift' | grep -vE 'import\s+(Foundation|Observation)\s*$'); then
  report "Domain은 Foundation 외 프레임워크를 import 할 수 없습니다:"$'\n'"$hits"
fi

if hits=$(grep -rnE '^\s*import\s+(Networking|MapUI|Feature[A-Za-z]*)\b' Sources/DesignSystem --include='*.swift'); then
  report "DesignSystem은 Networking·MapUI·Feature 모듈을 import 할 수 없습니다:"$'\n'"$hits"
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi
echo "check-architecture: OK"
