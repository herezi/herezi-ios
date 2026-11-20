#!/usr/bin/env bash
# xcodebuild -destination 값으로 쓸 iOS 시뮬레이터 UDID를 하나 고른다.
# 우선순위: $SIMULATOR_ID > 이미 부팅된 iPhone > 사용 가능한 첫 iPhone.
# 새 런타임을 내려받지 않고, 설치된 것만 사용한다.
set -euo pipefail

if [[ -n "${SIMULATOR_ID:-}" ]]; then
  echo "$SIMULATOR_ID"
  exit 0
fi

xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
iphones = []
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    for d in items:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            iphones.append((runtime, d))
if not iphones:
    sys.exit("pick-simulator: 사용 가능한 iPhone 시뮬레이터가 없습니다 (xcrun simctl list devices available).")
booted = [d for _, d in iphones if d["state"] == "Booted"]
# 최신 런타임 우선
iphones.sort(key=lambda x: [int(p) for p in x[0].rsplit("iOS-", 1)[-1].split("-") if p.isdigit()], reverse=True)
print((booted or [iphones[0][1]])[0]["udid"])
'
