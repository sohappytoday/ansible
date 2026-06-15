---
name: omc-docs
description: oh-my-claudecode 공식 GitHub 레포 내용만 참고해서 질문에 답한다. omc 사용법, 스킬 작성법, 설정 방법을 물을 때 사용한다.
argument-hint: <질문 또는 주제>
disable-model-invocation: true
---

# OMC Docs

oh-my-claudecode 공식 레포(https://github.com/Yeachan-Heo/oh-my-claudecode)의 내용만을 근거로 질문에 답한다.

## 사용법

```
/omc-docs <질문>
```

### 예시

```
/omc-docs SKILL.md frontmatter 필드가 뭐가 있어?
/omc-docs 스킬 파이프라인 어떻게 연결해?
/omc-docs external-context 스킬은 어떻게 동작해?
```

## 프로토콜

### Step 1: 관련 페이지 검색

WebSearch로 oh-my-claudecode 레포 내 관련 내용을 찾는다.

```
site:github.com/Yeachan-Heo/oh-my-claudecode <질문 키워드>
```

### Step 2: 내용 fetch

검색 결과에서 관련성 높은 페이지를 WebFetch로 가져온다.
- `skills/<skill-name>/SKILL.md` — 스킬 관련 질문
- `docs/REFERENCE.md` — 전반적인 사용법
- `README.md` — 개요 및 설치

### Step 3: 답변

fetch한 내용만을 근거로 답한다.
레포에 없는 내용은 "oh-my-claudecode 레포에서 관련 내용을 찾을 수 없습니다"라고 명시한다.

## 출력 형식

```markdown
## $ARGUMENTS

### 답변
<fetch한 내용 기반 답변>

### 출처
- [파일명](GitHub URL)
```
