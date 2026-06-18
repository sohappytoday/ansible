# 아키텍처 및 디렉토리 구조

## 아키텍처

**CP 1개 (단순 구성):**
```
Control Plane ×1
    │
Worker Node ×N
```

**CP 3개 이상 홀수 (HA 구성):**
```
VIP (Keepalived)
    │
  HAProxy (Active/Standby)
    │
Control Plane ×3+  ← stacked etcd
    │
Worker Node ×N
```

| 항목 | 값 |
|---|---|
| Control Plane 수 | `cp_count` — 1(단순) 또는 3 이상 홀수(HA) |
| Worker Node 수 | `worker_count` — 제한 없음 |
| LB VIP | `k8s_vip` — cp_count ≥ 3일 때만 설정 |
| K8s 버전 | `k8s_version` — 1.24 이상, 마이너 버전 지정 |
| CRI | `cri_type`: containerd / crio / docker |
| CRI 버전 | `cri_version` — 비우면 최신 stable |
| CNI | `cni_type`: calico / flannel / cilium |
| Pod CIDR | `k8s_pod_cidr` — 비우면 CNI별 기본값 자동 적용 |
| Service CIDR | `k8s_service_cidr` — 기본값: 10.96.0.0/12 |

**CNI별 Pod CIDR 기본값:**

| CNI | 기본 Pod CIDR |
|---|---|
| calico | 192.168.0.0/16 |
| flannel | 10.244.0.0/16 |
| cilium | 10.0.0.0/8 |

**CP 수에 따른 조건부 실행:**

| cp_count | control-plane-join.yml | lb.yml |
|---|---|---|
| 1 | 건너뜀 | 건너뜀 |
| 3 이상 (홀수) | 실행 | 실행 |

---

## 디렉토리 구조

```
~/terraform/
└── templates/               # terraform 명령 실행 위치
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── provider.tf
    ├── control-plane.tfvars
    ├── worker-node.tfvars
    └── modules/

ansible/
├── CLAUDE.md
├── inventory/
│   ├── cluster-hosts.yml          # Terraform output → 자동 생성
│   └── generate-cluster-hosts.sh
├── install-kubernetes-playbook.yml
└── roles/
    └── install_kubernetes/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml                   # 진입점
        │   ├── prerequisites.yml
        │   ├── cri-containerd.yml         # cri_type=containerd
        │   ├── cri-crio.yml               # cri_type=crio
        │   ├── cri-docker.yml             # cri_type=docker
        │   ├── install.yml                # kubeadm, kubelet, kubectl
        │   ├── control-plane-init.yml
        │   ├── control-plane-join.yml     # cp_count >= 3 일 때만
        │   ├── worker-join.yml
        │   ├── cni-calico.yml             # cni_type=calico
        │   ├── cni-flannel.yml            # cni_type=flannel
        │   ├── cni-cilium.yml             # cni_type=cilium
        │   ├── lb.yml                     # cp_count >= 3 일 때만
        │   ├── offline-prepare-packages.yml  # [CP] worker용 .deb 다운로드
        │   ├── offline-install-packages.yml  # [worker] .deb 오프라인 설치
        │   ├── offline-prepare-images.yml    # [CP] 이미지 export
        │   └── offline-install-images.yml    # [worker] 이미지 import
        └── templates/
```

---

## 폐쇄망 worker 오프라인 설치

worker가 인터넷 아웃바운드 차단(private subnet) 환경이면 `install_kubernetes_offline_worker: true`로 설정한다.
worker는 인터넷 설치(cri/install)를 건너뛰고, CP에서 받은 .deb/이미지로 오프라인 설치한다.

| 변수 | 설명 |
|---|---|
| `install_kubernetes_offline_worker` | true면 worker 오프라인 경로 (기본 false) |

**전제:** CP와 worker가 동일 OS/아키텍처 (Ubuntu 24.04 / amd64 등) → .deb·이미지 호환

**흐름:**
```
CP (인터넷 O)
  ├─ 인터넷 설치 (containerd, kubeadm…)
  ├─ offline-prepare-packages → worker용 .deb 다운로드 → 제어노드로 fetch
  ├─ control-plane-init → CNI 설치 → CP에 이미지 캐시
  └─ offline-prepare-images → pause/kube-proxy/CNI 이미지 export → 제어노드로 fetch

worker (인터넷 X)
  ├─ offline-install-packages → .deb 복사 → 로컬 설치 (apt-get install ./*.deb)
  ├─ offline-install-images → 이미지 tar 복사 → ctr import
  └─ worker-join (이미지 준비 후)
```

> 실행 순서상 worker-join은 CNI 설치 + 이미지 import 이후에 실행된다 (online/offline 공통).

---

## Inventory 형식

`inventory/cluster-hosts.yml` (generate-cluster-hosts.sh로 자동 생성):

```yaml
all:
  children:
    control_plane:
      hosts:
        master-1:
          ansible_host: <public_ip>
          ansible_user: ubuntu
          ansible_become: true
    worker_nodes:
      hosts:
        worker-1:
          ansible_host: <private_ip>
          ansible_user: ubuntu
          ansible_become: true
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -J ubuntu@<master_ip>'
  vars:
    cp_count: 1
    worker_count: 2
    k8s_version: "1.30"
    cri_type: "containerd"
    cri_version: ""
    cni_type: "calico"
    k8s_pod_cidr: ""
    k8s_vip: ""
    k8s_service_cidr: "10.96.0.0/12"
```

> Worker 노드는 CP를 점프 호스트로 사용해 private IP로 접근한다.

---

## Agent Delegation

| 에이전트 | 사용 시점 |
|---|---|
| `k8s-architect` | 새 role 설계, 아키텍처 결정, 플레이북 구조 검토 |
| `k8s-executor` | 플레이북 실행, Terraform apply, 실제 변경 작업 |
| `k8s-verifier` | 클러스터 상태 점검, 설치 후 검증 |
