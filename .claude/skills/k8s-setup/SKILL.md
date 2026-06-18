---
name: k8s-setup
description: 신규 Kubernetes HA 클러스터를 처음부터 구축한다. K8s 버전, CRI, CNI를 대화형으로 선택한 뒤 Terraform VM 프로비저닝 → 인벤토리 생성 → K8s 설치 전 파이프라인을 단계별로 안내한다.
argument-hint: "[단계명] config|terraform|inventory|k8s|all (기본값: all)"
---

> 실행 전 `.claude/docs/architecture.md`를 읽어라.

# K8s 신규 클러스터 구축

## 0단계: 구성 선택

플레이북 실행 전 아래 항목들을 사용자에게 선택받는다.
선택 결과를 `inventory/cluster-hosts.yml`의 `vars` 섹션과 `~/terraform/templates/` tfvars에 반영한다.

### 노드 수

```
Control Plane 수:
  1         → 단순 구성 (HAProxy/Keepalived 없음)
  3 이상 홀수 → HA 구성 (HAProxy + Keepalived 필요, k8s_vip 설정 필요)

Worker Node 수:
  제한 없음 (1 이상)

→ cp_count: <선택>
→ worker_count: <선택>
→ k8s_vip: "<VIP IP>"  # cp_count >= 3 일 때만 설정
```

> CP 수를 홀수로 유지해야 etcd 쿼럼이 보장된다. (2, 4개는 불가)

### K8s 버전

지원 범위: **1.24 이상** (dockershim 제거 이후)

```
선택 가능한 버전 (예시):
  1.24 / 1.25 / 1.26 / 1.27 / 1.28 / 1.29 / 1.30 / 1.31

→ k8s_version: "<선택>"
```

최신 stable 버전은 아래 명령으로 확인:
```bash
curl -s https://dl.k8s.io/release/stable.txt
```

### Container Runtime

| 선택 | cri_type 값 | 특징 |
|---|---|---|
| containerd | `containerd` | K8s 공식 권장, 가장 범용 |
| CRI-O | `crio` | RedHat/OpenShift 생태계, 경량 |
| Docker + cri-dockerd | `docker` | 기존 Docker 환경 마이그레이션용. K8s 1.24에서 dockershim 제거로 직접 지원 종료, cri-dockerd 어댑터를 통해 사용. 신규 구축엔 비권장 |

버전 미지정(`cri_version: ""`) 시 apt/dnf 저장소 최신 stable 자동 설치.  
특정 버전 고정 시 예: `cri_version: "1.7.0"` (containerd 기준)

> `docker` 선택 시 Docker Engine + cri-dockerd 두 가지가 함께 설치된다.

### CNI

| 선택 | cni_type 값 | Pod CIDR 기본값 | 특징 |
|---|---|---|---|
| Calico | `calico` | 192.168.0.0/16 | 네트워크 정책 지원, 가장 일반적 |
| Flannel | `flannel` | 10.244.0.0/16 | 단순, 네트워크 정책 미지원 |
| Cilium | `cilium` | 10.0.0.0/8 | eBPF 기반, 고성능, 고급 관측성 |

`k8s_pod_cidr`을 비워두면 선택한 CNI의 기본값이 자동 적용된다.

### 선택 결과 반영 (group_vars/all.yml)

> 구성 변수는 `inventory/group_vars/all.yml`에 `install_kubernetes_*` 접두사로 저장한다.
> `cluster-hosts.yml`은 generate 스크립트가 매번 덮어쓰므로 vars를 거기 두면 날아간다.
> **항상 먼저 `all.yml`이 있는지 + 구성이 채워져 있는지 확인하고, 없으면 0단계 선택값으로 새로 만든다.**

```bash
# 기존 구성 확인 — 없거나 비어 있으면 새로 생성
test -s inventory/group_vars/all.yml && cat inventory/group_vars/all.yml
```

없을 경우 `inventory/group_vars/all.yml`을 아래 형식으로 생성한다:

```yaml
---
# install_kubernetes role 구성 변수 (0단계 선택 결과)
install_kubernetes_cp_count: <선택>          # 1(단순) | 3+(HA 홀수)
install_kubernetes_worker_count: <선택>
install_kubernetes_version: "<선택>"          # 예: "1.30"
install_kubernetes_cri_type: "<선택>"         # containerd | crio | docker
install_kubernetes_cni_type: "<선택>"         # calico | flannel | cilium
install_kubernetes_offline_worker: <true|false>  # worker 폐쇄망 여부
# 선택 항목 (기본값 사용 시 생략 가능)
# install_kubernetes_cri_version: ""          # 비우면 최신 stable
# install_kubernetes_pod_cidr: ""             # 비우면 CNI별 기본값
# install_kubernetes_vip: ""                  # cp_count >= 3 일 때만
```

이미 있으면 값이 0단계 선택과 일치하는지 확인하고, 다르면 사용자 확인 후 갱신한다.

---

### worker 폐쇄망 여부

worker 노드가 인터넷 아웃바운드 차단(private subnet) 환경이면 오프라인 설치가 필요하다.

```
→ install_kubernetes_offline_worker: true   # worker가 폐쇄망일 때
```

> true면 worker는 CP에서 .deb·이미지를 받아 설치한다. CP와 worker가 동일 OS/아키텍처여야 한다.
> SSH도 worker는 CP 경유(ProxyCommand)로만 접근됨에 유의.

---

## 전제 조건 확인

구성 선택 완료 후:
- `terraform/` 디렉토리에 `main.tf`, `variables.tf`, `outputs.tf` 존재 여부
- `inventory/generate-cluster-hosts.sh` 존재 여부
- SSH 키 경로 (`ansible_ssh_private_key_file`) 설정 여부

---

## 파이프라인

### 1단계: Terraform (VM 프로비저닝)

```bash
# 자동 실행 가능
cd ~/terraform/templates && terraform plan --var-file=control-plane.tfvars --var-file=worker-node.tfvars

# 승인 필요
cd ~/terraform/templates && terraform apply --var-file=control-plane.tfvars --var-file=worker-node.tfvars
```

### 2단계: 인벤토리 생성 (항상 재생성)

> **반드시 매 구축마다 재생성한다.** 인스턴스를 stop/start하면 public IP는 물론
> private IP까지 바뀐다. 기존 `cluster-hosts.yml`이 있어도 신뢰하지 말고, terraform
> output 기준으로 항상 새로 생성한 뒤 사용한다.

```bash
# terraform output(IP)과 현재 cluster-hosts.yml이 일치하는지 먼저 비교
cd ~/terraform/templates && terraform output
# 일치 여부와 무관하게 항상 재생성 (드리프트 방지)
./inventory/generate-cluster-hosts.sh
```

생성된 `inventory/cluster-hosts.yml` 확인:
- control_planes 그룹 노드 수 (단순 1 / HA 3+)
- workers 그룹 노드 수
- HA 구성 시 loadbalancers 그룹 2개 (keepalived_priority 100/90)
- master public IP / worker private IP가 terraform output과 일치하는지
- vars 섹션에 선택한 k8s_version, cri_type, cni_type 반영 여부

### 3단계: 연결 확인

```bash
ansible all -i inventory/cluster-hosts.yml -m ping
ansible-playbook -i inventory/cluster-hosts.yml install-kubernetes-playbook.yml --check
```

> ping이 `UNREACHABLE`/`Connection timed out`이면 먼저 인벤토리 IP가 terraform
> output과 일치하는지 확인한다(2단계 재생성 누락이 가장 흔한 원인). IP가 맞는데도
> 막히면 control-plane SG의 `ssh_allowed_cidr`에 제어노드 IP가 포함됐는지 본다.

### 4단계: 클러스터 구축

```bash
ansible-playbook -i inventory/cluster-hosts.yml install-kubernetes-playbook.yml
```

내부적으로 `install_kubernetes` role의 `tasks/main.yml`이 아래 순서로 파일을 호출한다.
`cp_count` 값에 따라 일부 단계는 조건부 실행된다.

```
tasks/
├── main.yml               ← import_tasks 순서 제어
├── prerequisites.yml      ← swap off, 커널 모듈, sysctl
├── cri-containerd.yml     ← cri_type=containerd 일 때
├── cri-crio.yml           ← cri_type=crio 일 때
├── cri-docker.yml         ← cri_type=docker 일 때
├── install.yml            ← kubeadm, kubelet, kubectl
├── control-plane-init.yml ← 첫 번째 CP (항상 실행)
├── control-plane-join.yml ← cp_count >= 3 일 때만 실행
├── worker-join.yml        ← Worker 노드
├── cni-calico.yml         ← cni_type=calico 일 때
├── cni-flannel.yml        ← cni_type=flannel 일 때
├── cni-cilium.yml         ← cni_type=cilium 일 때
└── lb.yml                 ← cp_count >= 3 일 때만 실행 (HAProxy + Keepalived)
```

---

## 완료 기준

모든 단계 완료 후 `/k8s-verify` 실행.

- 모든 노드 `Ready`
- `kube-system` 네임스페이스 Pod 모두 `Running`
- etcd 멤버 3개 정상
- HAProxy VIP로 API server 접근 가능
