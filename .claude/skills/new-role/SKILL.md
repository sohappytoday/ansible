---
name: new-role
description: 새 Ansible role의 표준 디렉토리 구조와 기본 파일들을 생성한다. K8s 프로젝트 컨벤션(변수 네이밍, 멱등성 패턴, OS 분기)을 적용한다.
argument-hint: "<role-name>  예: k8s_containerd"
---

> 실행 전 `.claude/docs/conventions.md`를 읽어라.

# 새 Ansible Role 생성

## 표준 구조 생성

`$ARGUMENTS`를 role 이름으로 사용.

```
roles/<role-name>/
├── defaults/
│   └── main.yml
├── tasks/
│   ├── main.yml
│   ├── ubuntu.yml     (OS 분기 필요 시)
│   └── redhat.yml     (OS 분기 필요 시)
├── handlers/
│   └── main.yml       (서비스 재시작 등 핸들러가 필요한 경우)
└── templates/
    └── (Jinja2 템플릿, 필요 시)
```

## 기본 파일 내용

### defaults/main.yml 템플릿

```yaml
---
# <role-name> 기본 변수
# 변수명 prefix: <role-name>_ (예: k8s_containerd_version)
<role-name>_version: ""
```

### tasks/main.yml 템플릿 (OS 분기 포함)

```yaml
---
- name: Check OS family
  assert:
    that:
      - ansible_os_family in ["Debian", "RedHat"]
    fail_msg: "지원하지 않는 OS: {{ ansible_os_family }}"

- import_tasks: ubuntu.yml
  when: ansible_os_family == "Debian"

- import_tasks: redhat.yml
  when: ansible_os_family == "RedHat"
```

### tasks/main.yml 템플릿 (단순, OS 분기 불필요)

```yaml
---
- name: Check if already installed
  stat:
    path: /usr/local/bin/<binary>
  register: binary_stat
  changed_when: false

- name: Install <role-name>
  # ...
  when: not binary_stat.stat.exists
```

## 컨벤션 체크리스트

생성 후 확인:
- [ ] 변수명에 role 이름 prefix 적용 (`<role-name>_xxx`)
- [ ] 조회성 task에 `changed_when: false`
- [ ] 설치 전 존재 여부 확인 (`stat` 또는 `command -v`)
- [ ] 서비스 재시작은 `handlers/`에 분리
- [ ] 지원 OS 명시 (Ubuntu / Rocky / RHEL)
