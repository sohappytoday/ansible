# 아키텍처 및 디렉토리 구조

## 아키텍처 (v3 — AWS Private 클러스터)

전 노드를 Private Subnet에 두고, 목적별로 진입 경로를 분리한다.

- **관리(kubectl/Ansible)**: SSM Session Manager 터널. 노드에 공인 IP·인바운드 포트 없음.
- **서비스(외부 사용자)**: Reverse Proxy(Public)가 유일한 입구 → worker NodePort → Ingress.
- **outbound(패키지/이미지)**: 전 노드 Private → NAT Instance 경유.
- **HA apiserver**: 내부 NLB가 6443 단일 엔드포인트(keepalived/HAProxy 미사용).

```
관리자 PC ──SSM 터널(SSH-over-SSM)──▶ Control Plane ×3 (Private, 인바운드 0)
                                          │  └ stacked etcd
                                  내부 NLB(6443) ── apiserver 단일 엔드포인트
                                          │
외부 사용자 ─80/443▶ Reverse Proxy(Public) ─30080▶ Worker ×N (Private)
                                                      └ Ingress(L7) → Pod

전 노드 (Private) ──▶ NAT Instance(Public) ──IGW──▶ 인터넷 (apt/dnf, 이미지 pull)
```

| 항목 | 값 |
|---|---|
| Control Plane 수 | `install_kubernetes_cp_count` — 1(단순) 또는 3 이상 홀수(HA) |
| Worker Node 수 | `install_kubernetes_worker_count` — 제한 없음 |
| HA 엔드포인트 | `install_kubernetes_control_plane_endpoint` — 내부 NLB DNS (cp≥3). terraform output `control_plane_endpoint`에서 인벤토리로 자동 주입 |
| (온프렘) VIP | `install_kubernetes_vip` — keepalived 사용 시에만. AWS에서는 미사용 |
| K8s 버전 | `install_kubernetes_version` — 1.24 이상, 마이너 버전 지정 |
| CRI | `install_kubernetes_cri_type`: containerd / crio / docker |
| CNI | `install_kubernetes_cni_type`: calico / flannel / cilium |
| Pod CIDR | `install_kubernetes_pod_cidr` — 비우면 CNI별 기본값 |
| Service CIDR | `install_kubernetes_service_cidr` — 기본값: 10.96.0.0/12 |
| Ingress NodePort | `install_kubernetes_ingress_nodeport` — 기본 30080. terraform `ingress_nodeport`와 일치 |

**CNI별 Pod CIDR 기본값:** calico `192.168.0.0/16` / flannel `10.244.0.0/16` / cilium `10.0.0.0/8`

**CP 수에 따른 조건부 실행:**

| cp_count | control-plane-join.yml | lb.yml (keepalived/HAProxy) |
|---|---|---|
| 1 | 건너뜀 | 건너뜀 |
| 3 이상 (홀수) | 실행 | **AWS(NLB)에서는 건너뜀** — `loadbalancers` 그룹이 없으면 자동 스킵. 온프렘 VIP 구성에서만 실행 |

> CP 수는 홀수로 유지해야 etcd 쿼럼이 보장된다(2, 4개 불가).
> HA 엔드포인트는 NLB가 담당하므로 클라우드에서는 keepalived/HAProxy를 쓰지 않는다.

---

## 노드 접근 (SSM)

전 노드가 Private이고 공인 IP·SSH 인바운드가 없다. Ansible은 **SSM Session Manager의
`AWS-StartSSHSession`을 ProxyCommand로** 써서 SSH 터널을 연다.

- `ansible_host` = EC2 **인스턴스 ID** (IP 아님)
- 연결 = `aws ssm start-session --target <id> --document-name AWS-StartSSHSession ...`
- 로컬 전제: AWS CLI v2 + **session-manager-plugin** + 자격증명(`ssm:StartSession`)
- SSM 프로파일(`AmazonSSMManagedInstanceCore`)이 전 노드에 부착돼 있어야 한다(terraform).

> SSM 부착은 외부 노출이 아니다. 인바운드 포트를 열지 않으며, 세션은 AWS 자격증명을
> 가진 주체(=관리자 본인)만 시작할 수 있다.

**로컬 kubectl**: SSM 포트포워딩으로 CP의 6443에 붙는다. 이를 위해 apiserver 인증서
SAN에 `127.0.0.1`을 포함시킨다(`--apiserver-cert-extra-sans 127.0.0.1`). NLB DNS는
`--control-plane-endpoint`로 지정되어 자동으로 SAN에 들어간다.

---

## 디렉토리 구조

```
~/terraform/
└── templates/               # terraform 명령 실행 위치
    ├── main.tf              # VPC, EC2(CP/worker), NAT, Reverse Proxy, NLB, NACL
    ├── iam.tf               # SSM IAM (instance profile)
    ├── variables.tf / outputs.tf / provider.tf
    ├── control-plane.tfvars / worker-node.tfvars
    └── modules/

ansible/
├── CLAUDE.md
├── inventory/
│   ├── cluster-hosts.yml          # generate 스크립트가 자동 생성 (SSM/instance ID)
│   ├── generate-cluster-hosts.sh  # terraform output → 인벤토리 (SSM ProxyCommand)
│   └── group_vars/all.yml         # 정적 구성(cp_count, version, cri, cni 등)
├── install-kubernetes-playbook.yml
└── roles/
    └── install_kubernetes/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml                   # 진입점(import 순서 제어)
        │   ├── prerequisites.yml          # swap off, 커널 모듈, sysctl
        │   ├── cri-containerd.yml / cri-crio.yml / cri-docker.yml
        │   ├── install.yml                # kubeadm, kubelet, kubectl
        │   ├── control-plane-init.yml     # 첫 CP (NLB endpoint + cert SAN)
        │   ├── control-plane-join.yml     # cp_count >= 3 일 때만
        │   ├── worker-join.yml
        │   ├── cni-calico.yml / cni-flannel.yml / cni-cilium.yml
        │   ├── ingress-nginx.yml          # Ingress Controller (NodePort 30080)
        │   ├── lb.yml                     # 온프렘 keepalived/HAProxy (AWS 미사용)
        │   ├── offline-prepare-packages.yml  # [CP] worker용 .deb 다운로드
        │   ├── offline-install-packages.yml  # [worker] .deb 오프라인 설치
        │   ├── offline-prepare-images.yml    # [CP] 이미지 export
        │   └── offline-install-images.yml    # [worker] 이미지 import
        └── templates/
```

---

## Ingress / 서비스 노출

외부 사용자 트래픽은 Reverse Proxy(Public)만 통과한다.

```
외부 사용자 ─80/443▶ Reverse Proxy(Public) ─30080▶ worker NodePort
                                                       └ ingress-nginx → Service → Pod
```

- `ingress-nginx.yml`이 첫 CP에서 ingress-nginx를 설치하고 controller Service의 http
  NodePort를 `install_kubernetes_ingress_nodeport`(기본 30080)로 고정한다.
- terraform이 RP→worker:30080 SG 규칙을 깔아둔다. 두 값(NodePort)은 반드시 일치해야 한다.

---

## 폐쇄망 worker 오프라인 설치 (온프렘/legacy)

worker가 인터넷 아웃바운드 차단 환경이면 `install_kubernetes_offline_worker: true`.
worker는 인터넷 설치를 건너뛰고 CP에서 받은 .deb/이미지로 오프라인 설치한다.

> **AWS v3에서는 NAT로 outbound가 가능하므로 `false`**(온라인 설치). 이 경로는
> NAT조차 없는 온프렘 폐쇄망용이다. 전제: CP와 worker가 동일 OS/아키텍처.

```
CP (인터넷 O)
  ├─ 인터넷 설치 (containerd, kubeadm…)
  ├─ offline-prepare-packages → worker용 .deb 다운로드 → 제어노드로 fetch
  ├─ control-plane-init → CNI 설치 → CP에 이미지 캐시
  └─ offline-prepare-images → pause/kube-proxy/CNI 이미지 export → 제어노드로 fetch
worker (인터넷 X)
  ├─ offline-install-packages → .deb 복사 → 로컬 설치
  ├─ offline-install-images → 이미지 tar 복사 → ctr import
  └─ worker-join (이미지 준비 후)
```

---

## Inventory 형식 (v3)

`inventory/cluster-hosts.yml` (generate-cluster-hosts.sh로 자동 생성):

```yaml
all:
  vars:
    install_kubernetes_control_plane_endpoint: "k8s-apiserver-nlb-xxxx.elb.ap-northeast-2.amazonaws.com"
  children:
    control_plane:
      hosts:
        master-1:
          ansible_host: i-0c0f855b56742e3f6        # 인스턴스 ID
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/terraform-key
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-2"'
          ansible_become: true
    worker_nodes:
      hosts:
        worker-1:
          ansible_host: i-0cb1cc68fdf26c840         # 인스턴스 ID (동일 SSM 방식)
          ...
```

> 정적 구성(cp_count, version, cri/cni 등)은 `inventory/group_vars/all.yml`에 둔다.
> `cluster-hosts.yml`은 generate 스크립트가 매번 덮어쓰므로 그곳의 vars는 동적 값
> (control_plane_endpoint)만 둔다. 전 노드 동일하게 SSM ProxyCommand로 접근한다.

---

## Agent Delegation

| 에이전트 | 사용 시점 |
|---|---|
| `k8s-architect` | 새 role 설계, 아키텍처 결정, 플레이북 구조 검토 |
| `k8s-executor` | 플레이북 실행, Terraform apply, 실제 변경 작업 |
| `k8s-verifier` | 클러스터 상태 점검, 설치 후 검증 |
