# HA Kubernetes Cluster 구축

[← README로 돌아가기](README.md)

Ansible + Terraform으로 kubeadm 기반 Kubernetes 클러스터를 자동 구축·운영하는 작업이다. *(진행 중)*

---

## 개요

- **프로비저닝** — Terraform으로 VM 생성, `generate-cluster-hosts.sh`가 terraform output을 읽어 인벤토리를 생성한다.
- **K8s** — kubeadm 기반, K8s 1.24 이상 (`k8s_version` 변수로 선택)
- **CRI** — containerd / CRI-O / Docker(cri-dockerd) 중 선택 (`cri_type`)
- **CNI** — Calico / Flannel / Cilium 중 선택 (`cni_type`)
- **구성** — 단일 Control Plane(단순), 또는 Control Plane 3대 이상 홀수인 **HA 구성**
  (HA일 때만 HAProxy + Keepalived VIP가 붙는다)
- **폐쇄망 Worker** — 인터넷 아웃바운드가 차단된 Worker는 Control Plane에서 `.deb`·이미지를 받아 **오프라인 설치**한다 (`install_kubernetes_offline_worker: true`)

구성 항목은 `inventory/group_vars/all.yml`에 `install_kubernetes_*` 변수로 저장된다.

---

## 실행 방법

```bash
# 1. 인벤토리 생성 (terraform output 기반, 매번 재생성 권장)
./inventory/generate-cluster-hosts.sh

# 2. 연결 확인
ansible all -i inventory/cluster-hosts.yml -m ping

# 3. 클러스터 구축
ansible-playbook -i inventory/cluster-hosts.yml install-kubernetes-playbook.yml
```

---

## 트러블 슈팅

containerd / Calico 기반으로 단일 Control Plane + 폐쇄망 Worker 구성을 구축하면서 겪은 일들이다.

### 1. 인스턴스 재시작 후 인벤토리 IP 불일치

Terraform으로 VM을 올린 뒤, 한동안 인스턴스를 stop/start 했다가 다시 클러스터를 구축하려 하니 모든 노드에서 SSH가 `Connection timed out` 났다.  
원인은 인벤토리(`cluster-hosts.yml`)에 박혀 있던 IP가 옛날 값이었기 때문이다. AWS는 EIP를 붙이지 않으면 인스턴스를 stop/start 할 때마다 public IP가 바뀌고, private IP도 재배치되며 달라질 수 있다.  
`terraform output`으로 실제 IP를 확인해 보니 인벤토리에 적힌 값과 전부 달랐다.

인벤토리는 `generate-cluster-hosts.sh`가 terraform output을 읽어 생성하므로, 스크립트를 다시 돌려 최신 IP로 재생성하니 바로 접속됐다.

```bash
./inventory/generate-cluster-hosts.sh
```

이 일을 겪고, 구축할 때마다 기존 인벤토리를 믿지 말고 **항상 terraform output 기준으로 재생성**하도록 절차를 바꿨다.

### 2. 폐쇄망 Worker의 CNI 이미지 누락

Worker 노드는 인터넷 아웃바운드가 차단된 private subnet에 있어, Control Plane(CP)에서 이미지를 받아 오프라인으로 설치한다.  
그런데 설치 후 Worker가 계속 `NotReady`였고, `calico-node` Pod가 `ImagePullBackOff` 상태였다.

확인해 보니 Worker의 containerd에는 calico 이미지 중 `typha`, `pod2daemon-flexvol` 정도만 들어와 있고, 정작 필요한 `node`, `cni`, `csi` 이미지가 빠져 있었다.  
원인은 **오프라인 이미지를 export하는 시점**이었다. Calico는 tigera-operator가 이미지를 *순차적으로* 받는데, 'CNI 이미지가 1개라도 있으면' 통과하도록 돼 있어서 아직 다 받아지지 않은 불완전한 목록을 export하고 있었다.

CP에는 이미지가 모두 있었으므로, 우선 CP에서 이미지를 다시 묶어 Worker로 보내 살려냈다.

```bash
# CP에서 calico 이미지를 하나의 tar로 export → scp로 worker 전달
sudo ctr -n k8s.io images export /var/tmp/calico-all.tar quay.io/calico/node:vX.Y.Z quay.io/calico/cni:vX.Y.Z ...
# worker에서 import
sudo ctr -n k8s.io images import /var/tmp/calico-all.tar
```

근본 원인이 export 타이밍이었으므로, operator가 이미지를 다 받을 때까지 **이미지 개수가 안정화(연속 폴링 동안 변동 없음)될 때까지 대기**한 뒤 export하도록 task를 고쳤다.

### 3. 대용량 파일 전송 중 Control Plane OOM

위 2번을 복구하던 중, CP의 이미지 tar(약 344MB)를 제어 노드로 가져오려고 Ansible `fetch` 모듈을 썼다.  
그런데 CP의 SSH가 통째로 먹통이 됐다. 콘솔 로그를 보니 OOM killer가 `apiserver`, `calico-typha`, `coredns` 등을 차례로 죽이고 있었다.

```
Out of memory: Killed process (apiserver)
Out of memory: Killed process (calico-typha)
```

`fetch` 모듈은 원격 파일을 **base64로 인코딩해 메모리에 통째로 올린 뒤** 가져온다. 344MB가 460MB+로 부풀면서, 메모리가 4GiB뿐인 CP가 스왑 thrashing에 빠졌고 sshd까지 응답하지 못한 것이다.  
AWS 상태 검사는 정상(`ok`)이었지만 OS userspace가 멈춰 있어, 결국 인스턴스를 재부팅(`aws ec2 reboot-instances`)해 복구했다. kubeadm 클러스터는 재부팅에 강해서 static pod(etcd / apiserver 등)가 자동으로 다시 떠 클러스터 상태 자체는 보존됐다.

복구 후에는 `fetch` 대신 **`scp`**로 전송했다. scp는 인코딩 없이 바이너리를 스트리밍하므로 메모리를 거의 쓰지 않는다.  
이 일로 **노드 간 대용량 파일 전송은 `fetch` / `copy` 모듈 대신 `scp`로 통일**한다는 규칙을 컨벤션에 못 박았다.

### 4. ubuntu 유저로 kubectl이 안 되던 문제

서버에 직접 ubuntu 계정으로 접속해 `kubectl get nodes`를 하니 admin.conf permission denied가 떴다.  
`kubeadm init`이 마지막에 안내하는 그 설정을 root에만 해두고, 정작 접속 계정에는 해주지 않았기 때문이다.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

role이 접속 유저(`ansible_user`)용 kubeconfig도 자동으로 설정하도록 추가해, 이후로는 서버에 들어가 바로 `kubectl`을 쓸 수 있게 했다.
