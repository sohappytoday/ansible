---
name: make-agent
description: "새 서브에이전트를 .claude/agents/에 만들 때 사용한다. '~하는 에이전트 만들어줘', '에이전트 생성', 'make agent' 같은 요청 시 반드시 사용. author(make-agent)와 reviewer(make-agent-reviewer) 2인 팀을 순차 호출해, reviewer가 PASS할 때까지(최대 2회 재시도) 잘 정의된 에이전트 정의 파일을 만든다. 이미 있는 에이전트를 손보는 일에는 쓰지 말 것(그건 직접 Edit)."
allowed-tools: Read, Write, Glob, Agent
---

# Make Agent Skill
author와 reviewer 2인 팀을 순차로 호출해, 트리거 중심 description·최소 권한 tools·자족적 본문을
갖춘 서브에이전트 정의 파일(`.claude/agents/*.md`)을 생성한다. reviewer가 PASS할 때까지 반복한다.

## Workflow

1. **입력 확인.**
   만들 에이전트가 맡을 작업 설명이 있는지 확인한다. 없으면 사용자에게 한 줄로 요청하고 종료한다.

2. **Author 호출.**
   `make-agent` 에이전트를 Agent 도구로 호출하고, 작업 설명을 프롬프트로 전달한다.
   결과물은 `.claude/agents/<name>.md`. author가 보고한 저장 경로를 기록한다.

3. **Reviewer 호출.**
   `make-agent-reviewer` 에이전트를 Agent 도구로 호출하고, 2번에서 기록한 파일 경로를 전달한다.
   reviewer의 출력(판정·만족도·발견)을 `_workspace/make-agent-review.md`에 기록한다.
   (`_workspace/`가 없으면 만든다.)

4. **판정 분기.**
   - **PASS**: 생성된 `.claude/agents/<name>.md`의 경로와 핵심 결정(선택한 tools·model·description 요지)을
     사용자에게 요약해 제시하고 완료한다.
   - **nonpass**: reviewer의 수정 지시를 프롬프트에 포함해 `make-agent`를 **같은 파일을 수정하도록** 재호출한다.
     그 뒤 3번(Reviewer)으로 복귀해 재검토한다. (최대 2회 재시도)

5. **루프 종료.**
   2회 재작성 후에도 nonpass면 "자동 승인 한계 도달 — 수동 검토 권장" 경고와 함께,
   마지막 파일 경로 + reviewer가 남긴 미해결 발견 목록을 정직하게 보고하고 종료한다(무한 루프 방지).

## 원칙
- PASS 기준은 reviewer가 판정한다: **필수 항목 전부 충족 + 검수 항목 90% 이상 만족**.
- author/reviewer는 서브에이전트라 서로를 호출하지 못한다. 이 루프의 오케스트레이션은 오직 이 skill이 맡는다.
