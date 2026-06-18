# Kubernetes Cluster Automation

Ansible + Terraform으로 Kubernetes 클러스터를 자동 구축·운영하는 프로젝트.

## Tech Stack

- Terraform (`~/terraform/templates/`) — VM 프로비저닝
- Ansible — K8s 설치 및 구성
- Kubernetes (kubeadm) — 최소 1.24, `k8s_version` 변수로 선택
- CRI — `cri_type`: containerd / crio / docker(cri-dockerd)
- CNI — `cni_type`: calico / flannel / cilium
- LB — HAProxy + Keepalived (cp_count ≥ 3인 HA 구성 시에만)
- OS — Ubuntu / Rocky Linux / RHEL
- worker 폐쇄망 — worker가 인터넷 차단 시 `install_kubernetes_offline_worker: true` (CP 경유 오프라인 설치, 상세 `.claude/docs/architecture.md`)

## 안전 규칙

자동 실행 가능: `terraform plan`, `ansible --check`, `kubectl get/describe/logs`, `ansible-playbook`

승인 필수:

| 작업 | 이유 |
|---|---|
| `terraform apply` | VM 생성/삭제 |
| `kubectl drain` / `kubectl delete node` | 서비스 중단 |
| `kubeadm reset` | 클러스터 파괴 |
| `etcdctl` 직접 조작 | 데이터 손실 |
| 인증서 갱신 | 클러스터 접근 불가 위험 |
| 버전 업그레이드 | 롤링 중단 |

## 상세 문서

- 아키텍처 · 인벤토리 · 디렉토리 구조 → `.claude/docs/architecture.md`
- Ansible 컨벤션 · K8s 운영 규칙 → `.claude/docs/conventions.md`
- S3 패키지 저장소 계획 → `.claude/docs/s3-plan.md`

## Legacy Playbooks

K8s와 무관한 인프라 모니터링 플레이북. 인벤토리: `inventory/hosts.yml`

| 플레이북 | 설명 |
|---|---|
| `install-node-exporter-playbook.yml` | Node Exporter 설치 |
| `server-spec-playbook.yml` | 서버 사양 수집 → Excel |
| `gpu-node-monitoring-playbook.yml` | GPU 노드 정보 DB Upsert |
| `gpu-metrics-playbook.yml` | GPU 실시간 메트릭 수집 |
| `install-docker-playbook.yml` | Docker 설치 |
