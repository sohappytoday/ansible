---
name: k8s-node-remove
description: K8s 클러스터에서 노드를 안전하게 제거한다. drain → delete → Ansible 정리 → Terraform 삭제 순서를 강제한다. 파괴적 작업으로 모든 단계에서 승인을 받는다.
argument-hint: "<node-name>  예: worker3"
---

# K8s 노드 제거

> **경고**: 이 작업은 되돌리기 어렵다. 각 단계 실행 전 반드시 사용자에게 설명하고 승인을 받는다.

## 사전 확인

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep <node-name>
```

제거 대상 노드에서 실행 중인 Pod 목록 확인. StatefulSet Pod가 있으면 추가 주의 필요.

## 파이프라인

### 1단계: 노드 Drain (승인 필요)

> **설명**: 노드의 Pod를 다른 노드로 이동시키고 새 Pod 스케줄링을 막습니다.

```bash
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force
```

drain 완료 확인:
```bash
kubectl get pods -A -o wide | grep <node-name>
```
DaemonSet Pod만 남아있어야 정상.

### 2단계: Ansible로 K8s 구성 정리 (승인 필요)

> **설명**: 대상 노드에서 kubeadm reset, containerd 중지를 수행합니다.

```bash
ansible-playbook playbooks/k8s-node-remove.yml \
  -i inventory/cluster-hosts.yml \
  -e target_node=<node-name>
```

### 3단계: 클러스터에서 노드 삭제 (승인 필요)

> **설명**: API server에서 노드 오브젝트를 삭제합니다.

```bash
kubectl delete node <node-name>
```

### 4단계: Terraform으로 VM 삭제 (승인 필요)

> **설명**: 클라우드 인프라에서 VM을 실제 삭제합니다.

`terraform/variables.tf`에서 노드 수 감소 후:

```bash
terraform -chdir=terraform plan   # 삭제 대상 확인
terraform -chdir=terraform apply  # 승인 후 실행
```

### 5단계: 인벤토리 갱신

```bash
./inventory/generate-cluster-hosts.sh
```

## Control Plane 제거 시 추가 주의사항

- 반드시 홀수 개 유지 (3개 → 1개 금지)
- etcd 멤버에서도 제거 필요:
  ```bash
  etcdctl member list
  etcdctl member remove <member-id>
  ```
