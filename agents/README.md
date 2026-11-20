# Herezi 에이전트 팀

역할 정의 원본은 이 `agents/` 폴더다. 일반 마크다운이라 어떤 LLM 도구든 읽을 수 있다.
Claude Code는 `.claude/agents` → `agents/` 심볼릭 링크로 서브에이전트를 자동 인식한다. 다른 도구(Codex, Cursor, Gemini 등)는 `AGENTS.md`의 안내에 따라 해당 역할 파일을 읽고 그 지침을 따른다.
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

- 모든 작업은 이슈 → 브랜치 → PR(`Closes #n`). PR은 `develop`으로, `main`은 출시 전용. 직접 푸시 금지.
- 승인되지 않은 기획을 근거로 코드를 쓰지 않는다 (`herezi-api/docs/product/`).
- 기준 문서: [SERVICE-PLAN](https://github.com/herezi/herezi-api/blob/develop/docs/product/SERVICE-PLAN.md) · [PRODUCT](https://github.com/herezi/herezi-api/blob/develop/docs/product/PRODUCT.md) · [TECH-PLAN](https://github.com/herezi/herezi-api/blob/develop/docs/product/TECH-PLAN.md) · [DATA-PLAN](https://github.com/herezi/herezi-api/blob/develop/docs/product/DATA-PLAN.md) · [openapi.yaml](https://github.com/herezi/herezi-api/blob/develop/api/openapi.yaml)
- 공통 역할 파일을 고치면 세 레포에 같이 반영한다.
