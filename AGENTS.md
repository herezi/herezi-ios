# AGENTS.md — herezi-ios

에이전트(와 사람)가 이 레포에서 일할 때 가장 먼저 읽는 문서. 규칙이 바뀌면 이 파일을 먼저 고친다.

## 이 레포는

Herezi(여기) iOS 앱. "지금 내 위치 주변에서 볼 만한 것"(축제·공연·전시·팝업·자연…)을 목록과 네이버 지도로 보여 준다.
Swift 6 · SwiftUI · iOS 17+ · XcodeGen · 네이버 지도 SDK(SPM).

## 기준 문서 (herezi-api 레포, 읽기 전용)

제품·기술 결정의 기준은 [herezi-api](https://github.com/herezi/herezi-api)에 있다. 여기서 고치지 않는다.

- [SERVICE-PLAN.md](https://github.com/herezi/herezi-api/blob/main/docs/product/SERVICE-PLAN.md) — 서비스 기획 (무엇을, 왜)
- [PRODUCT.md](https://github.com/herezi/herezi-api/blob/main/docs/product/PRODUCT.md) — 제품 스펙
- [TECH-PLAN.md](https://github.com/herezi/herezi-api/blob/main/docs/product/TECH-PLAN.md) — 기술 기획 (스택, 일정, 개발 방식)
- [api/openapi.yaml](https://github.com/herezi/herezi-api/blob/main/api/openapi.yaml) — API 계약 (단일 기준)

이 레포의 결정 기록: [docs/adr/](docs/adr/).

## 폴더 지도

```
project.yml              XcodeGen 정의 (.xcodeproj는 생성물, 커밋 안 함) — ADR 0002
Config/                  xcconfig. Secrets.xcconfig는 gitignored, 예시는 Secrets.example.xcconfig
api/openapi.yaml         herezi-api 계약 사본 (make sync-api로만 갱신, 직접 수정 금지)
Sources/
  Domain/                모델·포트(SpotsService, LocationProviding)·FakeSpotsService. Foundation만 — ADR 0001
  Networking/            계약의 HTTP 어댑터 (APIClient, DTO, LiveSpotsService)
  MapUI/                 네이버 지도 래퍼. NMapsMap을 import하는 유일한 곳 — ADR 0003
  Features/Nearby/       "지금 내 주변" 화면 + NearbyViewModel
  Features/SpotDetail/   상세 화면
  App/                   조립(composition root), CoreLocation 어댑터
Tests/HereziTests/       단위 테스트(Swift Testing) + Fixtures/ (계약 형태의 JSON)
scripts/                 sync-api, check-architecture, check-api-drift, pick-simulator
docs/adr/                결정 기록
docs/exec-plans/         실행 계획 (active/ → completed/)
```

의존 방향: `Domain` ← `Networking`, `MapUI` ← `Features/*` ← `App`. Features는 Networking을 모른다.

## 명령

| 명령 | 하는 일 |
|---|---|
| `make generate` | `project.yml` → `Herezi.xcodeproj` (XcodeGen) |
| `make check` | **PR 전 필수.** lint + 아키텍처/계약 검사 + 빌드 + 시뮬레이터 테스트. CI와 같다 |
| `make test` | 빌드 + 테스트만 |
| `make lint` / `make format` | `xcrun swift-format` (Xcode 툴체인에 없으면 건너뜀) |
| `make sync-api` | herezi-api의 `api/openapi.yaml` 복사 (`../herezi-api` 또는 GitHub main) |
| `make clean` | 생성물 삭제 |

- 필요 도구: Xcode 26+, `brew install xcodegen`.
- 시뮬레이터는 `scripts/pick-simulator.sh`가 설치된 것 중에서 고른다(부팅된 iPhone 우선). `SIMULATOR_ID=<udid>`로 지정 가능.
- 빌드 산출물 위치: `DERIVED_DATA=<경로> make check` (기본 `build/DerivedData`, gitignored).
- 앱 실행: Debug는 서버 없이 샘플 데이터(`FakeSpotsService`)로 뜬다. 실제 API를 쓰려면 스킴 환경 변수 `HEREZI_FAKE_API=0`.
- 지도: `Config/Secrets.example.xcconfig`를 `Config/Secrets.xcconfig`로 복사해 NCP Client ID를 넣는다. 없어도 빌드·테스트는 된다.

## 규칙

1. **기획 먼저, 코드는 나중.** 새 기능·구조 변경은 `docs/exec-plans/active/`에 계획을 쓰고 승인받은 뒤 시작한다.
   기술 선택을 바꾸려면 herezi-api `TECH-PLAN.md` 또는 이 레포 ADR을 먼저 고친다.
2. **이슈 → 브랜치 → PR.** 모든 작업은 GitHub 이슈에서 시작해 브랜치(`feat/…`, `fix/…`, `chore/…`)에서 하고,
   PR 본문에 `Closes #n`을 쓴다. **main에 직접 푸시하지 않는다.** `make check`와 CI가 통과해야 머지한다.
3. **계약은 herezi-api가 기준.** `api/openapi.yaml`을 여기서 고치지 않는다. 바꿀 일이 있으면 herezi-api에 이슈/PR을 먼저 내고,
   머지 후 `make sync-api` → 코드 수정. `scripts/check-api-drift.sh`가 `Category` enum, `Spot`/`SpotPage`/`SpotMap` 필드, `/v1` 경로 구현 여부를 대조한다.
   - 예: v1.0에서 `free` 카테고리는 없어졌다. 무료는 `Spot.isFree` + 쿼리 `free=true`(`SpotQuery.freeOnly`)다.
4. **모듈 경계를 지킨다** (ADR 0001). 지도 SDK는 MapUI에서만, Features는 Domain 포트에만 의존.
5. **테스트.** 뷰모델·매핑 로직은 `FakeSpotsService`/픽스처로 단위 테스트를 같이 쓴다. 네트워크·위치에 의존하는 테스트 금지.
6. **비밀값 커밋 금지.** `Config/Secrets.xcconfig`, API 키, 인증서. 커밋은 파일을 명시해서 stage 한다(`git add -A` 금지).
7. 문서·주석은 한국어, 식별자는 영어. 커밋 메시지는 한국어 conventional 스타일(`feat: …`, `fix: …`, `chore: …`).
8. `.xcodeproj`, `Sources/App/Info.plist`는 생성물이다. 설정은 `project.yml`/`Config/*.xcconfig`에서 고친다.

## 알려진 기술 부채

- Release용 API 호스트 미정 (`project.yml` `HEREZI_API_BASE_URL`).
- 네이버 지도 SDK 헤더의 iOS 26 deprecation 경고를 에러에서 제외 중 (ADR 0003).
- 계약 드리프트 검사는 `Category`, 응답 스키마 3개(`Spot`/`SpotPage`/`SpotMap`) 필드, `/v1` 경로 존재만 본다(쿼리 파라미터는 단위 테스트로). 계약이 커지면 생성기(swift-openapi-generator 등) 검토.

## 에이전트 역할
역할별 지침은 [`agents/`](agents/README.md)에 있다(기획자·디자이너·리뷰어·QA·개발자). 어떤 LLM 도구든 역할을 맡으면 해당 파일(`agents/<역할>.md`)을 먼저 읽고 따른다. Claude Code는 `.claude/agents` 링크로 자동 인식한다.
