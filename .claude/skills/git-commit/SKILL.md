---
name: git-commit
description: AngularJS 컨벤션으로 변경 사항을 분석하고 git add, commit, push를 수행한다. 사용자가 명시적으로 /git-commit 으로 호출할 때만 실행된다.
argument-hint: "[커밋 메시지 힌트 — 생략 가능]"
---

# Git Commit

AngularJS commit convention에 따라 변경 사항을 분석하고, 커밋 메시지를 제안한 뒤 사용자 승인 후
`git add .` → `git commit` → `git push`를 수행한다.

## AngularJS Commit Convention

```
<type>(<scope>): <subject>
<빈 줄>
<body — 선택>
<빈 줄>
<footer — 선택>
```

### Type

| Type | 사용 상황 |
|------|----------|
| feat | 새로운 기능 추가 |
| fix | 버그 수정 |
| docs | 문서 수정 |
| style | 코드 포맷 변경 (기능 변경 없음) |
| refactor | 리팩토링 (기능 변경·버그 수정 없음) |
| perf | 성능 개선 |
| test | 테스트 추가·수정 |
| chore | 빌드 설정, 패키지 관리 등 |

### Subject 규칙

- 명령형으로 작성 (`add` not `added`)
- 첫 글자 소문자
- 끝에 마침표 없음
- 72자 이내
- 한국어 기본, 기술 용어·모듈명·리소스명은 영어 허용
  - 예: `add ec2 instance type variable`
  - 예: `S3 remote backend 설정 추가`
  - 예: `refactor(network): VPC subnet 분리`

---

## 실행 절차

### Step 1: 변경 사항 파악

아래 명령으로 변경 내용을 확인한다.

```bash
git status
git diff
git diff --staged
```

파일 목록과 변경 내용을 분석해 적절한 type, scope, subject를 결정한다.

### Step 2: 커밋 메시지 초안 작성

- `$ARGUMENTS`가 있으면 커밋 메시지 힌트로 활용한다.
- 변경 파일이 여러 type에 걸쳐 있으면 가장 핵심적인 type 하나를 선택한다.
- scope는 변경 범위를 나타내는 짧은 명사 (예: `ec2`, `variables`, `network`, `iam`, `backend`)

### Step 3: 사용자 확인

커밋 메시지 초안을 보여주고 승인을 받는다.

```
다음 메시지로 커밋하겠습니다:

  feat(variables): add ec2 instance type variable

진행할까요? [y] 승인 / [n] 취소 / 수정할 내용 직접 입력
```

사용자가 수정 내용을 입력하면 그 내용으로 메시지를 바꾸고 다시 확인한다.

### Step 4: 실행

승인 후 아래 순서로 실행한다.

```bash
git add .
git commit -m "$(cat <<'EOF'
<커밋 메시지>
EOF
)"
git push
```

### Step 5: main 브랜치 동기화

현재 브랜치가 `v1`, `v2`, `v3` 등 버전 브랜치이면 push 후 main도 동일 커밋으로 업데이트한다.

```bash
CURRENT=$(git branch --show-current)
git checkout main
git merge --ff-only "$CURRENT"
git push origin main
git checkout "$CURRENT"
```

- `--ff-only` — fast-forward가 불가능하면 중단한다. 강제 merge하지 않는다.
- 버전 브랜치가 아닌 경우(예: `feature/xxx`)에는 이 단계를 건너뛴다.

### Step 6: 결과 확인

```bash
git log --oneline -3
```

push 결과와 최근 커밋 3개를 출력한다.

---

## 규칙

- `Co-authored-by` 트레일러를 **절대** 추가하지 않는다.
- 사용자 승인 없이 커밋·푸시를 실행하지 않는다.
- `--no-verify` 플래그를 사용하지 않는다.
- 자동 트리거되지 않는다 — 반드시 `/git-commit` 으로 명시 호출해야 실행된다.
