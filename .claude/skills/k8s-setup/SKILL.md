---
name: k8s-setup
description: 신규 Kubernetes HA 클러스터를 처음부터 구축한다. K8s 버전, CRI, CNI를 대화형으로 선택한 뒤 Terraform VM 프로비저닝 → 인벤토리 생성 → K8s 설치 전 파이프라인을 단계별로 안내한다.
argument-hint: "[단계명] config|terraform|inventory|k8s|all (기본값: all)"
---

# K8s 신규 클러스터 구축

## 0단계: 구성 선택

플레이북 실행 전 아래 3가지를 사용자에게 선택받는다.
선택 결과를 `inventory/cluster-hosts.yml`의 `vars` 섹션에 반영한다.

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

### 선택 결과 반영

`inventory/cluster-hosts.yml` vars 섹션:

```yaml
vars:
  k8s_version: "<선택>"       # 예: "1.30"
  cri_type: "<선택>"          # containerd | crio
  cri_version: ""             # 특정 버전 고정 시 입력, 기본값: 최신
  cni_type: "<선택>"          # calico | flannel | cilium
  k8s_pod_cidr: ""            # 기본값 사용 시 빈칸 유지
```

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

### 2단계: 인벤토리 생성

```bash
./inventory/generate-cluster-hosts.sh
```

생성된 `inventory/cluster-hosts.yml` 확인:
- control_planes 그룹 3개 노드
- workers 그룹 노드 수
- loadbalancers 그룹 2개 (keepalived_priority 100/90)
- vars 섹션에 선택한 k8s_version, cri_type, cni_type 반영 여부

### 3단계: 연결 확인

```bash
ansible all -i inventory/cluster-hosts.yml -m ping
ansible-playbook -i inventory/cluster-hosts.yml install-kubernetes-playbook.yml --check
```

### 4단계: 클러스터 구축

```bash
ansible-playbook -i inventory/cluster-hosts.yml install-kubernetes-playbook.yml
```

내부적으로 `install_kubernetes` role의 `tasks/main.yml`이 아래 순서로 파일을 호출한다:

```
tasks/
├── main.yml               ← import_tasks 순서 제어
├── prerequisites.yml      ← swap off, 커널 모듈, sysctl
├── cri-containerd.yml     ← cri_type=containerd 일 때
├── cri-crio.yml           ← cri_type=crio 일 때
├── cri-docker.yml         ← cri_type=docker 일 때
├── install.yml            ← kubeadm, kubelet, kubectl
├── control-plane-init.yml ← 첫 번째 CP
├── control-plane-join.yml ← 나머지 CP
├── worker-join.yml        ← Worker 노드
├── cni-calico.yml         ← cni_type=calico 일 때
├── cni-flannel.yml        ← cni_type=flannel 일 때
├── cni-cilium.yml         ← cni_type=cilium 일 때
└── lb.yml                 ← HAProxy + Keepalived
```

---

## 완료 기준

모든 단계 완료 후 `/k8s-verify` 실행.

- 모든 노드 `Ready`
- `kube-system` 네임스페이스 Pod 모두 `Running`
- etcd 멤버 3개 정상
- HAProxy VIP로 API server 접근 가능
