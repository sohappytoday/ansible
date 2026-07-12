---
name: k8s-build
description: "신규 Kubernetes HA 클러스터를 서브에이전트 팀(k8s-architect 설계 → k8s-executor 실행 → k8s-verifier 검증)으로 처음부터 구축할 때 사용한다. 'HA 클러스터 구축해줘', 'K8s 클러스터 처음부터 세팅' 같은 요청 시 사용. 0단계에서 노드 수·K8s 버전·CRI·CNI·offline을 대화로 선택하고, terraform apply와 설치조건 확정 두 지점에서 사용자 승인을 받은 뒤 자동으로 프로비저닝·설치·검증까지 진행한다. 단순 상태 점검만 필요하면 /k8s-verify, 수동 단계별 절차 참조는 k8s-setup을 쓸 것. 노드 추가/제거에는 쓰지 말 것(/k8s-node-add, /k8s-node-remove)."
argument-hint: "[단계명] config|terraform|inventory|k8s|all (기본값: all)"
disable-model-invocation: true
allowed-tools: Read, Write, Glob, Bash, Agent
---

> 실행 전 `.claude/docs/architecture.md`를 읽어라.

# K8s Build — 서브에이전트 팀 클러스터 구축

`k8s-architect`(설계) → `k8s-executor`(실행) → `k8s-verifier`(검증) 3인 팀을 지휘해
v3 AWS Private Kubernetes HA 클러스터를 구축한다. 순서·루프·재시도·사용자 승인은 전부 이 스킬이
쥔다. 에이전트는 격리 컨텍스트의 headless 워커이며 되물을 수 없으므로, 승인이 필요한 정보는
에이전트가 리포트의 `## 승인 필요` 블록으로 반환하고 **이 스킬이 사용자에게 묻는다.**

중간 산출물은 모두 `_workspace/k8s-build/` 아래에 둔다. 없으면 먼저 생성한다:
```bash
mkdir -p _workspace/k8s-build
```

`$ARGUMENTS`로 시작 단계(config|terraform|inventory|k8s|all, 기본값 all)를 받는다. 지정이
없으면 `all`로 0단계부터 완주한다.

---

## 0단계 — 입력 확인 + 구성 선택 (스킬 ↔ 사용자 대화)

헤드리스 에이전트가 못 하는 대화이므로 메인 컨텍스트(이 스킬)가 직접 진행한다.
아래 6개 값을 사용자에게 선택받는다:

- `cp_count` — 1(단순) | 3 이상 홀수(HA, etcd 쿼럼). 짝수 불가.
- `worker_count` — 1 이상.
- `version` — 1.24 이상 (예: "1.30").
- `cri_type` — containerd | crio | docker.
- `cni_type` — calico | flannel | cilium.
- `offline_worker` — true|false (AWS v3 기본 false).

기존 구성이 있으면 **먼저 보여주고 재사용/변경을 확인**한다:
```bash
test -s inventory/group_vars/all.yml && cat inventory/group_vars/all.yml
```
- 있으면: 내용을 제시하고 "이 구성 재사용 / 변경"을 묻는다. 재사용이면 아래 architect 호출에
  "기존 all.yml 재사용" 지시를 넘긴다. 변경이면 변경 필드를 함께 넘긴다.
- 없거나 비어 있으면: 위 6개 값을 대화로 선택받는다.

선택값이 확정되면 게이트①로 넘어간다.

## 게이트① — terraform apply 여부 (스킬 ↔ 사용자)

"terraform apply가 됐는가(VM/노드가 이미 떠 있는가)?"를 묻는다.
답을 `applied=true|false`로 확정해 architect 프롬프트에 넘긴다.

---

## 설계 — `k8s-architect` 호출

`Agent` 도구로 `k8s-architect`를 호출한다. 프롬프트에 다음을 문자 그대로 담는다:

- 0단계 선택값(cp_count / worker_count / version / cri_type / cni_type / offline_worker)
  **또는** "기존 all.yml 재사용" 지시 (+ 변경 요청 필드).
- `applied` 플래그(게이트① 응답, true/false).
- 읽을 참조: `inventory/group_vars/all.yml`, `.claude/docs/architecture.md`,
  (applied=true면) `~/terraform/templates`의 `terraform output`.
- 계약: `inventory/group_vars/all.yml`을 `install_kubernetes_*` 접두 정적 구성으로 확정하고,
  `_workspace/k8s-build/config-report.md`에 `## all.yml 확정 내용`, `## 드리프트 대조`,
  `## 승인 필요` 세 섹션을 문자 그대로 작성해 반환할 것. 스스로 승인하지 말 것.

호출 후 `_workspace/k8s-build/config-report.md`를 Read한다.

## 승인 게이트 A — 설치조건 확정 (스킬 ↔ 사용자)

config-report.md의 **`## 승인 필요` 블록**(설치조건 표 + 드리프트 경고 + 유효성 경고)을
사용자에게 그대로 제시하고 **"이대로 진행 / 변경"을 명시적으로 묻는다.**

- "이대로 진행" → 다음 단계로.
- "변경" → 변경 내용을 프롬프트에 담아 `k8s-architect`를 재호출(all.yml 갱신 후 config-report
  재생성)하고 다시 제시한다.
- **최대 재시도 3회.** 소진 시 **"구성 미확정 — 3회 내 승인 없음"으로 종료**하고 마지막
  config-report 요약을 보고한다.

확정된 `cp_count` / `cni_type` / `applied` 값을 이후 단계에서 재사용한다.

---

## 1단계 — Terraform (applied=false일 때만)

applied=true면 이 단계 전체를 건너뛴다.

### 1a. plan — `k8s-executor` 호출

`Agent`로 `k8s-executor`를 호출한다. 프롬프트:
- `phase=terraform-plan`.
- terraform은 `~/terraform/templates`에서 두 var-file(control-plane.tfvars,
  worker-node.tfvars)로 실행. **apply는 절대 실행하지 말 것.**
- 계약: 변경 요약 + `## 승인 필요` 블록을 `_workspace/k8s-build/plan-report.md`로 반환.

호출 후 `_workspace/k8s-build/plan-report.md`를 Read한다.

### 승인 게이트 B — apply 승인 (스킬 ↔ 사용자)

plan-report.md의 변경 요약과 `## 승인 필요` 블록을 제시하고 **apply 승인을 명시적으로 받는다**
(비가역·과금 작업임을 알린다).
- 미승인 → **"apply 미승인으로 종료"**하고 보고.
- 승인 → 1b로.

### 1b. apply — `k8s-executor` 호출

`Agent`로 `k8s-executor`를 호출한다. 프롬프트:
- `phase=terraform-apply`. (게이트 B 승인 후에만 호출)
- `~/terraform/templates`에서 두 var-file로 `terraform apply` 실행.
- 계약: apply 결과 요약(성공/실패, 신규 리소스)을 반환.

apply 실패면 원인을 보고하고 종료한다.

---

## 2단계 — 인벤토리 재생성 (항상)

`Agent`로 `k8s-executor`를 호출한다. 프롬프트:
- `phase=inventory`. 필요 시 환경값(SSH_KEY / AWS_REGION)을 넘긴다(없으면 스크립트 기본값 사용).
- `./inventory/generate-cluster-hosts.sh`로 `inventory/ha-cluster-ssm.yml`을 재생성.
- 계약: `control_plane`/`worker_nodes` 노드 수, `ansible_host`=instance ID,
  `install_kubernetes_control_plane_endpoint`=NLB DNS 검증을
  `_workspace/k8s-build/inventory-report.md`로 반환.

이 단계 산출물 `inventory/ha-cluster-ssm.yml`을 이후 connectivity/install/verifier가 소비한다.

## 3단계 — 연결 확인

`Agent`로 `k8s-executor`를 호출한다. 프롬프트:
- `phase=connectivity`. 대상 인벤토리 `inventory/ha-cluster-ssm.yml`.
- `ansible all -i inventory/ha-cluster-ssm.yml -m ping` + `--check` 플레이북.
- 계약: ping 결과 + `--check` diff 요약, UNREACHABLE이면 원인 진단(인벤토리 드리프트 / SG)을
  `_workspace/k8s-build/preflight-report.md`로 반환.

호출 후 `_workspace/k8s-build/preflight-report.md`를 Read한다.
- 정상 → 설치 최종 확인으로.
- UNREACHABLE/실패 → **2단계(인벤토리 재생성)를 1회 재시도**한 뒤 다시 connectivity를 호출한다.
  그래도 실패면 **"연결 실패 — 인벤토리/SG 수동 조치 필요"로 종료**하고 preflight-report 진단을
  보고한다.

## 설치 go/no-go 최종 확인 (스킬 ↔ 사용자)

승인 게이트 A에서 확정된 조건으로 실제 설치를 진행할지 한 줄 go/no-go를 묻는다.
- no → 종료.
- go → 4단계로.

---

## 4단계 — 클러스터 구축

`Agent`로 `k8s-executor`를 호출한다. 프롬프트:
- `phase=install`. 대상 인벤토리 `inventory/ha-cluster-ssm.yml`.
- `ansible-playbook -i inventory/ha-cluster-ssm.yml install-kubernetes-playbook.yml` 실행.
- 계약: 플레이북 recap + 실패 태스크를 `_workspace/k8s-build/install-report.md`로 반환.

## 검증 루프 (판정 분기 + 최대 재시도)

`Agent`로 `k8s-verifier`를 호출한다. 프롬프트:
- 확정 구성 `cp_count`, `cni_type` (승인 게이트 A 확정값).
- 인벤토리 경로 `inventory/ha-cluster-ssm.yml`.
- 참조: `.claude/skills/k8s-verify/SKILL.md`(점검 항목), `.claude/docs/architecture.md`(완료 기준).
- 계약: 노드 Ready / kube-system Running / etcd healthy / 선택 CNI Running / NLB 6443
  (127.0.0.1:6443) 점검 후 `_workspace/k8s-build/verify-report.md`를 반환하되
  **첫 줄이 반드시 `판정: PASS` 또는 `판정: FAIL`**일 것.

호출 후 `_workspace/k8s-build/verify-report.md`를 Read하고 **첫 줄을 파싱**한다:

- **`판정: PASS`** → 완료 보고로.
- **`판정: FAIL`** → verify-report의 실패 항목(원인·조치)을 프롬프트에 담아
  `k8s-executor`를 `phase=install`로 **재호출**(플레이북은 멱등)한 뒤 `k8s-verifier`로 **재검증**한다.
  - **최대 재시도 2회.** 소진 시 **"검증 미통과 — 수동 조치 필요"로 종료**하고, 마지막
    verify-report의 미해결 실패 항목을 정직하게 보고한다.

---

## 완료 보고

- 최종 verify-report 요약(노드 N/N Ready, 시스템 Pod, etcd healthy, CNI Running, NLB 6443 응답).
- 생성/변경된 파일 목록: `inventory/group_vars/all.yml`, `inventory/ha-cluster-ssm.yml`,
  `_workspace/k8s-build/`의 각 리포트.
- 승인받은 게이트 이력: 게이트①(applied), 승인 게이트 A(설치조건), 승인 게이트 B(apply, 해당 시),
  설치 go/no-go.
- 재시도 소진·미승인·연결 실패 등으로 중단됐다면 그 사유와 미해결 항목을 정직하게 명시한다.

## 원칙

- 순서·루프·재시도·승인 질문은 전부 이 스킬이 쥔다. 에이전트끼리 서로 호출하지 않는다.
- 판정은 `k8s-verifier`의 몫이다. 이 스킬은 첫 줄 `판정:`을 뒤집지 않고 분기만 한다.
- 이름·경로는 실제 `.claude/agents/*.md`와 리포트 경로가 정본이다. 어긋나면 실제 파일을 따른다.
- 파괴적 작업(terraform destroy, kubeadm reset, kubectl drain/delete node, etcdctl member
  remove/del)은 어떤 단계에서도 지시하지 않는다. 실패 복구는 멱등 플레이북 재실행뿐이다.
