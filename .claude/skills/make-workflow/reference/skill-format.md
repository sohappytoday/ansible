# SKILL.md(.claude/skills/*/SKILL.md) 정본 스펙

skill-author와 skill-reviewer가 공유하는 단일 기준 문서. Claude Code 공식 문서(code.claude.com/docs/en/skills)를 근거로 한다.

## 스킬의 정체

SKILL.md 하나 = 스킬 하나. **커맨드명(`/이름`)은 디렉토리명에서 온다** — frontmatter `name`은 목록에 표시되는 라벨일 뿐이다. 파일 위치: `.claude/skills/<커맨드명>/SKILL.md`.

## frontmatter

**모든 필드가 선택**이다. 단 `description`은 사실상 필수(Claude가 로드 여부를 판단하는 근거).

| 필드 | 의미 |
| --- | --- |
| `name` | 목록 표시용 라벨. 생략 시 디렉토리명 |
| `description` | 무엇을 하고 **언제 쓰는지**. 핵심 유스케이스를 맨 앞에. `when_to_use`와 합쳐 **1,536자에서 잘림** |
| `when_to_use` | 트리거 문구·예시 요청 등 추가 신호. description 뒤에 이어 붙음 |
| `argument-hint` | 자동완성에 보이는 인자 힌트. 예: `[워크플로 설명]` |
| `arguments` | `$이름` 치환용 이름 있는 위치 인자 목록 |
| `disable-model-invocation` | `true`면 Claude가 자동 호출 못 함(사용자 `/이름` 전용). 배포·커밋처럼 부작용 있는 워크플로에 사용 |
| `user-invocable` | `false`면 `/` 메뉴에서 숨김(배경지식 전용) |
| `allowed-tools` | 스킬 활성 중 **묻지 않고 허용**할 도구. 제한이 아니라 권한 부여 |
| `disallowed-tools` | 스킬 활성 중 도구 풀에서 제거할 도구 |
| `model` / `effort` | 스킬 활성 중 모델/노력 수준 오버라이드 |
| `context: fork` + `agent` | 스킬을 서브에이전트 컨텍스트에서 실행 |
| `paths` | 이 glob에 걸리는 파일 작업 중일 때만 자동 로드 |

### 필드 결정 원칙
- **description = 로드 트리거.** "언제"를 구체적으로: 사용자 요청 문구 예시, 경계, 반례("~에는 쓰지 말 것"). 비슷한 스킬이 있으면 한 구절로 구분. 동작 방식(HOW)은 본문 몫.
- **부작용이 있는 워크플로**(배포, 커밋, 외부 발행)는 `disable-model-invocation: true`를 고려한다.
- **allowed-tools는 최소로.** 본문 절차가 실제로 쓰는 도구만. 오케스트레이션 스킬이면 `Agent`가 필요하다.

## 본문(스킬이 로드되면 컨텍스트에 상주)

- **500줄 이하.** 상세 자료는 `reference/` 등 supporting file로 빼고, SKILL.md에서 "그 파일에 무엇이 있고 **언제 읽어야 하는지**"를 명시한다.
- **간결·지시형.** 로드된 본문은 턴마다 토큰 비용이다. 이유 서술 대신 "무엇을 하라"를 쓴다.
- `$ARGUMENTS`, `$0`/`$1`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}` 치환을 쓸 수 있다.

### 오케스트레이션 스킬(여러 에이전트를 지휘하는 스킬)의 본문 필수 요소

이 저장소의 워크플로 스킬(make-agent, make-workflow 등)은 아래를 모두 갖춘다:

1. **입력 확인** — 필요한 입력이 없으면 사용자에게 한 줄로 요청하고 종료.
2. **단계별 에이전트 호출** — 어떤 에이전트를 `Agent` 도구로, 어떤 프롬프트(경로·계약 포함)로 부르는지 명시. **에이전트 이름은 `.claude/agents/<name>.md`의 `name`과 정확히 일치**해야 한다.
3. **판정 분기와 루프** — reviewer PASS/nonpass에 따른 분기, **최대 재시도 횟수**(무한 루프 방지).
4. **정직한 실패 종료** — 재시도 소진 시 경고 + 미해결 목록을 보고하고 종료.
5. **중간 산출물 경로** — 에이전트 간 주고받는 파일은 `_workspace/` 아래 경로를 명시.

## 스킬 vs 에이전트 (역할 구분)

- **스킬** = 메인 컨텍스트에서 도는 절차·지식. 사용자와 대화 가능, 여러 에이전트 지휘 가능.
- **에이전트** = 격리 컨텍스트의 워커. headless(사용자에게 못 되물음), 자기 산출물만 계약대로 내놓음.
- 오케스트레이션(순서·루프·재시도)은 스킬이 쥔다. 에이전트 정의 스펙은 `agent-format.md`(make-agent 모듈의 reference)를 따른다.
