# Herezi 에이전트 팀

이 폴더의 서브에이전트는 Claude Code가 자동으로 인식한다(`.claude/agents/*.md`).
세 레포(`herezi-api`, `herezi-ios`, `herezi-android`)에 같은 공통 역할이 있고, 개발자 역할만 레포마다 다르다.

| 에이전트 | 역할 | 코드 수정 | 있는 레포 |
|---|---|---|---|
| `planner` | 기획자: 기획 문서·이슈·수용 기준 | 문서만 | 전부 |
| `designer` | 디자이너: 화면 스펙·디자인 토큰·시안·UI 리뷰 | 디자인 문서·에셋만 | 전부 |
| `reviewer` | 코드 리뷰어: PR 정확성·계약·규칙 위반 | ✕ (읽기 전용) | 전부 |
| `qa` | QA: 수용 기준 검증·테스트 작성·실행·버그 이슈 | 테스트만 | 전부 |
| `api-dev` / `data-curator` | Go 서버 개발 / 공공데이터 수집·검증 | ○ | herezi-api |
| `ios-dev` | SwiftUI 개발 | ○ | herezi-ios |
| `android-dev` | Compose 개발 | ○ | herezi-android |

## 기본 흐름

```
planner(이슈 + 수용 기준) → designer(화면 스펙, 앱 기능일 때) → *-dev(브랜치·구현·PR)
   → reviewer(PR 리뷰) → qa(수용 기준 검증) → 머지 → 이슈 닫힘
```

- 모든 작업은 이슈 → 브랜치 → PR(`Closes #n`). main 직접 푸시 금지.
- 승인되지 않은 기획을 근거로 코드를 쓰지 않는다 (`herezi-api/docs/product/`).
- 기준 문서: [SERVICE-PLAN](https://github.com/herezi/herezi-api/blob/main/docs/product/SERVICE-PLAN.md) · [PRODUCT](https://github.com/herezi/herezi-api/blob/main/docs/product/PRODUCT.md) · [TECH-PLAN](https://github.com/herezi/herezi-api/blob/main/docs/product/TECH-PLAN.md) · [DATA-PLAN](https://github.com/herezi/herezi-api/blob/main/docs/product/DATA-PLAN.md) · [openapi.yaml](https://github.com/herezi/herezi-api/blob/main/api/openapi.yaml)
- 공통 역할 파일을 고치면 세 레포에 같이 반영한다.
