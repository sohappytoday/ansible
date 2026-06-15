# Kubernetes HA Cluster Automation

Ansible + Terraform으로 Kubernetes HA 클러스터를 자동 구축·운영하는 프로젝트.

---

## Tech Stack

- **인프라 프로비저닝**: Terraform
- **구성 자동화**: Ansible
- **Orchestration**: Kubernetes (kubeadm) — `k8s_version` 변수로 선택, **최소 1.24**
- **Container Runtime**: containerd / CRI-O — `cri_type` 변수로 선택
- **CNI**: Calico / Flannel / Cilium — `cni_type` 변수로 선택
- **LB**: HAProxy + Keepalived (VIP)
- **etcd**: stacked (Control Plane 내장)
- **OS**: Ubuntu / Rocky Linux / RHEL

---

## Architecture

```
VIP (Keepalived)
    │
  HAProxy (Active/Standby)
    │
Control Plane ×3  ← stacked etcd
    │
Worker Node ×N
```

| 항목 | 값 |
|---|---|
| Control Plane | 3개 (홀수, stacked etcd) |
| LB VIP | `k8s_vip` 변수로 정의 |
| K8s 버전 | `k8s_version` — 1.24 이상, 마이너 버전 지정 (예: "1.30") |
| CRI | `cri_type`: `containerd` / `crio` |
| CRI 버전 | `cri_version` — 미지정 시 최신 stable |
| CNI | `cni_type`: `calico` / `flannel` / `cilium` |
| Pod CIDR | `k8s_pod_cidr` — CNI별 기본값 자동 적용 |
| Service CIDR | `k8s_service_cidr` — 기본값: 10.96.0.0/12 |

**CNI별 Pod CIDR 기본값:**

| CNI | 기본 Pod CIDR |
|---|---|
| calico | 192.168.0.0/16 |
| flannel | 10.244.0.0/16 |
| cilium | 10.0.0.0/8 |

---

## Code Organization

```
ansible/
├── CLAUDE.md
├── terraform/                     # VM 프로비저닝
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── inventory/
│   ├── cluster-hosts.yml          # Terraform output → 자동 생성
│   └── generate-cluster-hosts.sh
├── playbooks/
│   ├── k8s-cluster-setup.yml
│   ├── k8s-node-add.yml
│   ├── k8s-node-remove.yml
│   └── k8s-upgrade.yml
└── roles/
    ├── k8s_prerequisites/         # swap off, 커널 모듈, sysctl
    ├── k8s_containerd/            # CRI: containerd  (cri_type=containerd)
    ├── k8s_crio/                  # CRI: CRI-O       (cri_type=crio)
    ├── k8s_install/               # kubeadm, kubelet, kubectl
    ├── k8s_control_plane_init/    # 첫 번째 CP: kubeadm init
    ├── k8s_control_plane_join/
    ├── k8s_worker_join/
    ├── k8s_calico/                # CNI: Calico      (cni_type=calico)
    ├── k8s_flannel/               # CNI: Flannel     (cni_type=flannel)
    ├── k8s_cilium/                # CNI: Cilium      (cni_type=cilium)
    ├── k8s_haproxy/
    └── k8s_keepalived/
```

---

## Development Rules

### Ansible Role 규칙

- `defaults/main.yml`에 기본값 선언, role 이름을 prefix로 사용 (`k8s_install_version`)
- 모든 task는 멱등성 보장 (`stat` / `command -v` / `when` 조합)
- 조회성 task에 `changed_when: false` 필수
- OS 분기는 `import_tasks: ubuntu.yml / redhat.yml` 패턴

### 안전 규칙

**확인 없이 자동 실행:**
- `terraform plan`, `terraform output`
- `ansible --check` (드라이런)
- `kubectl get`, `kubectl describe`, `kubectl logs`
- `ansible-playbook` (설치·설정 성격의 idempotent 작업)

**반드시 설명 후 승인 필요:**

| 작업 | 이유 |
|---|---|
| `terraform apply` | 실제 VM 생성/삭제 |
| `kubectl drain` / `kubectl delete node` | 서비스 중단 가능 |
| `kubeadm reset` | 클러스터 파괴 |
| `etcdctl` 직접 조작 | 데이터 손실 위험 |
| 인증서 갱신 | 오설정 시 클러스터 접근 불가 |
| 버전 업그레이드 | 롤링 중단 발생 |

### K8s 운영 체크리스트

노드 유지보수 전:
1. `kubectl get nodes` — 모든 노드 Ready 확인
2. `kubectl get pods -A | grep -v Running` — 비정상 Pod 확인
3. etcd 스냅샷 백업: `etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db`

업그레이드 순서: CP 노드 먼저 → Worker 순. 마이너 버전 1단계씩.

---

## Agent Delegation

| 에이전트 | 사용 시점 |
|---|---|
| `k8s-architect` | 새 role 설계, 아키텍처 결정, 플레이북 구조 검토 |
| `k8s-executor` | 플레이북 실행, Terraform apply, 실제 변경 작업 |
| `k8s-verifier` | 클러스터 상태 점검, 설치 후 검증 |

---

## Inventory 형식

```yaml
all:
  children:
    control_planes:
      hosts:
        cp1: { ansible_host: 10.0.1.10 }
        cp2: { ansible_host: 10.0.1.11 }
        cp3: { ansible_host: 10.0.1.12 }
    workers:
      hosts:
        worker1: { ansible_host: 10.0.2.10 }
    loadbalancers:
      hosts:
        lb1: { ansible_host: 10.0.0.10, keepalived_priority: 100 }
        lb2: { ansible_host: 10.0.0.11, keepalived_priority: 90 }
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/k8s-key

    # K8s 버전 (1.24 이상, 마이너 버전 지정)
    k8s_version: "1.30"

    # Container Runtime: containerd | crio
    cri_type: "containerd"
    cri_version: ""             # 비워두면 최신 stable

    # CNI: calico | flannel | cilium
    cni_type: "calico"
    k8s_pod_cidr: ""            # 비워두면 CNI별 기본값 자동 적용

    # 네트워크
    k8s_vip: "10.0.0.100"
    k8s_service_cidr: "10.96.0.0/12"
```

---

## Current Focus

- [ ] K8s HA 클러스터 roles 구현 (prerequisites → containerd → install → init → join → CNI → LB)
- [ ] Terraform 코드 작성 (VM 프로비저닝)
- [ ] generate-cluster-hosts.sh Terraform output 연동

## 패키지 저장소 계획 (S3 기반 NAS)

Claude가 패키지 버전을 확인할 때 할루시네이션이 발생하는 문제를 방지하기 위해 AWS S3를 내부 패키지 저장소로 활용한다.

**저장 대상:**
- K8s 바이너리 (kubeadm, kubelet, kubectl) — 버전별
- CRI 패키지 (containerd, CRI-O)
- CNI manifest (Calico, Flannel, Cilium YAML/Helm chart)

**Ansible 연동 방식:**
```yaml
# 인터넷 대신 S3에서 다운로드
- name: Download kubectl
  get_url:
    url: "https://{{ s3_bucket }}.s3.{{ aws_region }}.amazonaws.com/k8s/{{ k8s_version }}/kubectl"
    dest: /usr/local/bin/kubectl

# 버전 존재 여부 사전 확인 — 없으면 fail (할루시네이션 방지)
- name: Verify version exists in S3
  command: aws s3 ls s3://{{ s3_bucket }}/k8s/{{ k8s_version }}/
  failed_when: version_check.rc != 0
  register: version_check
```

**변수 (inventory/cluster-hosts.yml에 추가 예정):**
```yaml
s3_bucket: "my-k8s-packages"
aws_region: "ap-northeast-2"
use_s3_mirror: true   # false면 공식 인터넷 저장소 사용
```

---

## Legacy Playbooks (기존 인프라 모니터링)

K8s와 무관하게 독립 운영 중인 플레이북. 인벤토리: `inventory/hosts.yml`

| 플레이북 | 설명 |
|---|---|
| `install-node-exporter-playbook.yml` | Node Exporter 설치 |
| `server-spec-playbook.yml` | 서버 사양 수집 → Excel |
| `gpu-node-monitoring-playbook.yml` | GPU 노드 정보 DB Upsert |
| `gpu-metrics-playbook.yml` | GPU 실시간 메트릭 수집 |
| `install-docker-playbook.yml` | Docker 설치 |
