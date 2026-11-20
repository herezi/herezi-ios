# ADR 0002: XcodeGen, .xcodeproj는 커밋하지 않음

- 상태: 승인 (2026-11-20)
- 근거: herezi-api `docs/product/TECH-PLAN.md` §2 (`herezi-ios`: XcodeGen, `.xcodeproj`는 생성물)

## 맥락

`.xcodeproj`(pbxproj)는 사람이 읽기 어렵고 병합 충돌이 잦다. 에이전트가 타깃·설정을 고칠 때
리뷰 가능한 텍스트 한 곳에서 고치는 편이 안전하다.

## 결정

- 프로젝트 정의는 `project.yml`(XcodeGen) 하나가 기준이다. `make generate`로 `Herezi.xcodeproj`를 만든다.
- `Herezi.xcodeproj`, 생성되는 `Sources/App/Info.plist`는 `.gitignore`에 있다. 직접 고치지 않는다.
- 빌드 설정: Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, 경고는 에러, iOS 17+.
- 비밀값은 `Config/Base.xcconfig`가 `#include? "Secrets.xcconfig"`(선택)로 읽는다.
  파일이 없어도 빌드·테스트는 통과한다. 예시는 `Config/Secrets.example.xcconfig`.

## 결과

- 처음 받은 뒤, 그리고 `project.yml`을 바꾼 뒤에는 `make generate`가 필요하다(`make check`는 자동 실행).
- CI는 `brew install xcodegen` 후 `make check`를 돌린다.
