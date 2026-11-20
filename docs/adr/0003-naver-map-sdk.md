# ADR 0003: 네이버 지도 SDK (SPM, MapUI 모듈로 격리)

- 상태: 승인 (2026-11-20)
- 근거: herezi-api `docs/product/TECH-PLAN.md` §2 "네이버 지도 (양 앱)"

## 맥락

국내 지도 품질과 네이버지도 앱 길찾기 연결(기획 P0) 때문에 네이버 지도를 쓴다.
외부 SDK가 앱 전체에 퍼지면 교체·테스트가 어려워진다.

## 결정

- SDK: 공식 SPM 래퍼 `https://github.com/navermaps/SPM-NMapsMap`, `exactVersion: 3.24.1` (`project.yml`).
- `NMapsMap`/`NMapsGeometry` import는 `Sources/MapUI`에서만 한다. 기능 화면은 `SpotMapView`(SwiftUI)와
  Domain 타입만 본다. `scripts/check-architecture.sh`가 검사한다.
- 인증: NCP Maps Client ID를 Info.plist `NMFNcpKeyId`로 넣는다. 값은 `Config/Secrets.xcconfig`의
  `NAVER_MAPS_CLIENT_ID`(gitignored). 없으면 빌드는 되고 지도만 런타임에 인증 오류를 표시한다.

## 알려진 문제

- SDK 3.24.1 헤더(`NMFUtils.h`)가 iOS 26에서 deprecated된 `UIScreen.mainScreen`을 사용한다.
  Swift warnings-as-errors가 clang 모듈 빌드에 `-Werror`로 전달돼 빌드가 깨지므로,
  `project.yml`에서 `OTHER_SWIFT_FLAGS: -Xcc -Wno-error=deprecated-declarations`로 이 경고만 에러에서 뺐다.
  SDK가 고쳐지면 이 플래그를 지운다.

## 결과

- SDK 버전을 올릴 때는 이 ADR의 버전과 "알려진 문제"를 함께 고친다.
