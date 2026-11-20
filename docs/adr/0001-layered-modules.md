# ADR 0001: 계층형 모듈 + 도메인 포트

- 상태: 승인 (2026-11-20)
- 근거: herezi-api `docs/product/TECH-PLAN.md` §2 "앱 아키텍처: 기능별 모듈 + 도메인 포트"

## 맥락

서버(herezi-api)는 아직 배포 전이고, 앱 화면은 서버 없이도 개발·테스트할 수 있어야 한다.
에이전트가 코드를 고칠 때 "어디에 무엇을 둬야 하는지"가 파일 구조만 보고 분명해야 한다.

## 결정

XcodeGen 타깃(=Swift 모듈)으로 계층을 나누고, 의존 방향을 한쪽으로만 둔다.

| 계층 | 타깃 | 의존 가능 | 내용 |
|---|---|---|---|
| 0 | `Domain` | Foundation | 모델(`Spot`, `SpotCategory`…), 포트(`SpotsService`, `LocationProviding`), `FakeSpotsService` |
| 1 | `Networking` | Domain | `api/openapi.yaml` 계약의 HTTP 어댑터(`LiveSpotsService`) |
| 1 | `MapUI` | Domain, NMapsMap | 네이버 지도 SwiftUI 래퍼. **NMapsMap을 import 하는 유일한 모듈** |
| 2 | `FeatureNearby`, `FeatureSpotDetail` | Domain, MapUI | 화면 + 뷰모델. Networking 의존 금지 |
| 3 | `Herezi`(앱) | 전부 | 조립(composition root). 구체 어댑터를 고르는 유일한 곳 |

- 기능은 `SpotsService` 프로토콜에만 의존하므로 `FakeSpotsService`로 프리뷰·테스트·오프라인 실행이 된다.
- Debug 빌드는 서버 배포 전까지 `FakeSpotsService`가 기본(`HEREZI_USE_FAKE_API`, 스킴 환경 변수 `HEREZI_FAKE_API`로 덮어쓰기).

## 강제

- 타깃 의존성은 `project.yml`에서 선언하므로 컴파일러가 막는다.
- import 규칙(지도 SDK는 MapUI만, Features→Networking 금지, Domain은 Foundation만)은
  `scripts/check-architecture.sh`가 `make check`에서 검사한다.

## 결과

- 새 화면은 `Sources/Features/<이름>`에 새 타깃으로 추가한다.
- 새 외부 SDK는 별도 계층 1 모듈로 감싸고, 이 ADR과 검사 스크립트를 함께 고친다.
