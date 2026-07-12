---
name: make-workflow
description: "스킬 1개 + 서브에이전트 팀 전체를 한 번에 설계·생성할 때 사용한다. '~하는 워크플로 만들어줘', 'generate→test→review처럼 여러 에이전트가 순서대로 도는 파이프라인이 필요해' 같은 요청 시 반드시 사용. architect가 팀을 설계하고, make-agent 팀이 에이전트들을, skill-author 팀이 스킬을 만들며, 마지막에 통합 검수한다. 단일 에이전트 하나만 필요하면 make-agent 스킬을 쓸 것. 기존 워크플로 수정에는 쓰지 말 것(그건 직접 Edit)."
argument-hint: "[만들 워크플로 설명]"
allowed-tools: Read, Write, Glob, Agent
---

# Make Workflow Skill

요청 하나를 받아 **완결된 워크플로**(오케스트레이션 스킬 1개 + 서로 맞물린 서브에이전트 N개)를
생성한다. 설계(architect) → 에이전트 생성 루프(make-agent 팀) → 스킬 생성 루프(skill-author 팀)
→ 통합 검수 순으로 진행한다. 중간 산출물은 `_workspace/<워크플로명>/`에 둔다.

## Workflow

1. **입력 확인.**
   만들 워크플로에 대한 설명(무슨 일을 하는지, 대략 어떤 단계가 필요한지)이 있는지 확인한다.
   없으면 사용자에게 한 줄로 요청하고 종료한다.

2. **설계 — `workflow-architect` 호출.**
   요청 설명을 프롬프트로 전달한다. 산출물: `_workspace/<워크플로명>/team-spec.md`.
   스펙이 나오면 **에이전트 목록·파이프라인·핵심 판단을 사용자에게 요약 제시하고 승인을 받는다.**
   사용자가 수정을 원하면 수정 사항을 포함해 architect를 재호출한다(최대 2회, 이후엔 사용자와
   직접 조율). 여기가 유일한 사용자 개입 지점이다 — 이후 단계는 자동으로 진행한다.

3. **에이전트 생성 — team-spec의 에이전트마다 반복.**
   "재사용"으로 표기된 에이전트는 건너뛴다. 새로 만들 에이전트 각각에 대해:
   1. `make-agent` 에이전트를 호출한다. 프롬프트에 team-spec 경로와 해당 에이전트 섹션
      (역할·입력·출력·상하류·tools/model 제안)을 포함하고, **I/O 계약을 그대로 지켜 작성**하라고
      지시한다. 산출물: `.claude/agents/<name>.md`.
   2. `make-agent-reviewer`를 호출해 그 파일을 검수한다. 결과를
      `_workspace/<워크플로명>/review-<name>.md`에 기록한다.
   3. nonpass면 수정 지시를 포함해 `make-agent`를 같은 파일 수정으로 재호출 후 재검수.
      **에이전트당 최대 2회 재시도.** 소진 시 해당 에이전트를 "미해결"로 표기하고 다음으로 진행한다.

4. **스킬 생성 — `skill-author` 호출.**
   프롬프트에 team-spec 경로와 3번에서 생성된 에이전트 파일 경로 전부를 전달한다.
   산출물: `.claude/skills/<커맨드명>/SKILL.md`.
   `skill-reviewer`로 검수하고 결과를 `_workspace/<워크플로명>/review-skill.md`에 기록한다.
   nonpass면 수정 지시를 포함해 `skill-author`를 재호출. **최대 2회 재시도.**

5. **통합 검수 — `workflow-integration-reviewer` 호출.**
   team-spec 경로와 생성된 파일 전체 목록을 전달한다.
   nonpass면 각 발견의 "수정 대상·재호출 지정"에 따라 `make-agent` 또는 `skill-author`를
   재호출해 고치고 재검수한다. **통합 라운드 최대 2회.**

6. **완료 보고.**
   생성된 파일 전체 목록(스킬 경로 + 에이전트 경로들), 파이프라인 요약, 각 에이전트의
   tools/model 결정을 사용자에게 제시한다. 미해결 발견이 하나라도 있으면
   "자동 승인 한계 도달 — 수동 검토 권장" 경고와 함께 미해결 목록을 정직하게 보고한다.
   새 `agents` 디렉토리가 이번에 처음 생긴 스코프라면 재시작해야 로드된다는 점을 안내한다.

## 원칙

- 오케스트레이션(순서·루프·재시도)은 이 스킬이 쥔다. 에이전트끼리 서로 호출하게 설계하지 않는다.
- 판정은 각 reviewer의 몫이다. 이 스킬은 판정을 뒤집지 않고 분기만 한다.
- 이름·경로는 실제 파일이 정본이다. 스펙과 어긋나면 실제 파일 기준으로 맞추고 어긋남을 보고한다.
- 정본 스펙: 스킬 형식은 [reference/skill-format.md](reference/skill-format.md), 팀 스펙 형식은
  [reference/team-spec.md](reference/team-spec.md), 에이전트 형식은
  `.claude/skills/make-agent/reference/agent-format.md`. 이 스킬 본문과 충돌하면 reference가 이긴다.
