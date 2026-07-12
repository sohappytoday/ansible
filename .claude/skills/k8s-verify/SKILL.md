---
name: k8s-verify
description: K8s 클러스터 전체 상태를 점검한다. 노드 상태, 시스템 Pod, etcd 헬스, 네트워크 연결을 확인한다. 읽기 전용 작업만 수행한다.
argument-hint: "[점검 범위] nodes|pods|etcd|network|all (기본값: all)"
---

> 실행 전 `.claude/docs/architecture.md`를 읽어라.

# K8s 클러스터 상태 검증

모든 명령은 읽기 전용. 자동 실행 가능.

## 1. 노드 상태

```bash
kubectl get nodes -o wide
```

**기대값**: 모든 노드 `Ready`, 버전 동일

## 2. 시스템 Pod 상태

```bash
kubectl get pods -n kube-system
kubectl get pods -A | grep -v Running | grep -v Completed
```

**기대값**: `kube-system` 네임스페이스 Pod 모두 `Running` 또는 `Completed`

## 3. etcd 헬스 (Control Plane 노드에서 실행)

```bash
# CP 노드에서 실행
ansible control_planes[0] -i inventory/ha-cluster-ssm.yml -a \
  "etcdctl endpoint health --cluster \
   --endpoints=https://127.0.0.1:2379 \
   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
   --cert=/etc/kubernetes/pki/etcd/server.crt \
   --key=/etc/kubernetes/pki/etcd/server.key"

# etcd 멤버 목록
ansible control_planes[0] -i inventory/ha-cluster-ssm.yml -a \
  "etcdctl member list --endpoints=https://127.0.0.1:2379 \
   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
   --cert=/etc/kubernetes/pki/etcd/server.crt \
   --key=/etc/kubernetes/pki/etcd/server.key"
```

**기대값**: 모든 etcd 멤버 `healthy`, 3개 멤버 존재

## 4. 네트워크 (Calico)

```bash
kubectl get pods -n calico-system
kubectl get nodes -o jsonpath='{.items[*].status.conditions}' | python3 -c \
  "import sys,json; [print(c) for item in json.loads(sys.stdin.read()) for c in item if c.get('type')=='NetworkUnavailable']"
```

**기대값**: Calico Pod 모두 Running, NetworkUnavailable=False

## 5. HAProxy/VIP 확인

```bash
# VIP로 API server 접근 테스트
curl -k https://<k8s_vip>:6443/healthz

# HAProxy 상태
ansible loadbalancers -i inventory/ha-cluster-ssm.yml -a "systemctl status haproxy"
ansible loadbalancers -i inventory/ha-cluster-ssm.yml -a "systemctl status keepalived"
```

**기대값**: `/healthz` → `ok`, haproxy/keepalived `active (running)`

## 검증 결과 요약 형식

```
✓ 노드: N개 Ready / N개 전체
✓ 시스템 Pod: N개 Running
✓ etcd: 3개 멤버 healthy
✓ Calico: Running
✓ VIP: 응답 정상
```

실패 항목이 있으면 원인과 조치 방법을 함께 보고한다.
