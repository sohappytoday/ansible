---
name: k8s-node-add
description: 기존 K8s 클러스터에 새 노드를 추가한다. Terraform으로 VM 생성 후 인벤토리 갱신, Ansible로 join 실행. worker 또는 control-plane 노드 모두 지원.
argument-hint: "<node-type> <node-name>  예: worker worker3 | control-plane cp4"
next-skill: k8s-verify
---

> 실행 전 `.claude/docs/architecture.md`를 읽어라.

# K8s 노드 추가

## 현재 상태 확인

```bash
kubectl get nodes -o wide
```

추가 전 모든 기존 노드 `Ready` 상태 확인.

## 파이프라인

### 1단계: Terraform으로 VM 추가

`terraform/variables.tf` 또는 `terraform/main.tf`에서 노드 수 변경 후:

```bash
cd ~/terraform/templates && terraform plan --var-file=control-plane.tfvars --var-file=worker-node.tfvars   # 자동 실행 — 변경사항 확인
cd ~/terraform/templates && terraform apply --var-file=control-plane.tfvars --var-file=worker-node.tfvars  # 승인 필요
```

### 2단계: 인벤토리 갱신

```bash
./inventory/generate-cluster-hosts.sh
```

`inventory/cluster-hosts.yml`에 새 노드가 추가되었는지 확인.

### 3단계: 새 노드만 대상으로 실행

**Worker 추가:**
```bash
ansible-playbook playbooks/k8s-node-add.yml \
  -i inventory/cluster-hosts.yml \
  --limit <node-name>
```

**Control Plane 추가 (주의: etcd 쿼럼 영향):**
```bash
# 기존 CP 노드에서 join 명령 생성
ansible control_planes[0] -i inventory/cluster-hosts.yml \
  -a "kubeadm token create --print-join-command --control-plane"

ansible-playbook playbooks/k8s-node-add.yml \
  -i inventory/cluster-hosts.yml \
  --limit <new-cp-name> \
  -e node_type=control-plane
```

## Control Plane 추가 시 주의사항

- Control Plane은 항상 홀수 개 유지 (3, 5, 7...)
- etcd 쿼럼이 깨지지 않도록 기존 멤버 상태 먼저 확인
- 추가 후 etcd 멤버 수 검증 필수
