#!/bin/bash
# terraform output을 읽어 ha-cluster-ssm.yml을 생성한다 (v3: 전 노드 Private + SSM 접근).
#
# v2와의 차이:
#   - 노드가 모두 Private Subnet에 있고 공인 IP가 없다. control-plane bastion(ProxyJump)도 없다.
#   - 따라서 ansible_host에 IP가 아니라 EC2 인스턴스 ID를 넣고,
#     SSM Session Manager(AWS-StartSSHSession)를 ProxyCommand로 써서 SSH 터널을 연다.
#   - apiserver 단일 엔드포인트는 내부 NLB의 DNS 이름(control_plane_endpoint)을 그대로 쓴다.
#
# 로컬 전제조건:
#   - AWS CLI v2 + session-manager-plugin 설치
#   - 대상 계정에 대한 자격증명(ssm:StartSession 권한)
#   - 노드 키페어 개인키(기본 ~/.ssh/terraform-key)
#
# 실행 전 terraform apply가 완료되어 있어야 한다 (control_plane_endpoint는 apply 후에야 생성됨).

set -euo pipefail

TERRAFORM_DIR="${TERRAFORM_DIR:-$HOME/terraform/templates}"
OUTPUT_FILE="$(cd "$(dirname "$0")" && pwd)/ha-cluster-ssm.yml"
SSH_KEY="${SSH_KEY:-~/.ssh/terraform-key}"

# SSM start-session에 넘길 리전. 환경변수/aws config에서 찾고, 없으면 기본값.
REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
REGION="${REGION:-ap-northeast-2}"

cd "$TERRAFORM_DIR" || { echo "terraform 디렉토리를 찾을 수 없습니다: $TERRAFORM_DIR"; exit 1; }

CONTROL_PLANE_IDS=$(terraform output -json control_plane_instance_ids 2>/dev/null || true)
if [ -z "$CONTROL_PLANE_IDS" ] || [ "$CONTROL_PLANE_IDS" = "{}" ]; then
  echo "control_plane_instance_ids를 가져올 수 없습니다. terraform apply가 완료됐는지 확인하세요."
  exit 1
fi

WORKER_IDS=$(terraform output -json worker_node_instance_ids 2>/dev/null || true)
if [ -z "$WORKER_IDS" ] || [ "$WORKER_IDS" = "{}" ]; then
  echo "worker_node_instance_ids를 가져올 수 없습니다."
  exit 1
fi

CP_ENDPOINT=$(terraform output -raw control_plane_endpoint 2>/dev/null || true)
if [ -z "$CP_ENDPOINT" ]; then
  echo "control_plane_endpoint를 가져올 수 없습니다. 내부 NLB가 생성됐는지 확인하세요."
  exit 1
fi

SSH_USER=$(terraform output -raw ssh_user 2>/dev/null || true)
if [ -z "$SSH_USER" ]; then
  echo "ssh_user를 가져올 수 없습니다."
  exit 1
fi

# SSM 터널 ProxyCommand. %h(=ansible_host=인스턴스 ID), %p(=포트)는 ssh가 치환한다.
SSM_PROXY="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ${REGION}"
SSH_COMMON="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"${SSM_PROXY}\""

# === all.vars: apply 후에만 알 수 있는 동적 값 ===
# control_plane_endpoint는 kubeadm --control-plane-endpoint로 쓰인다.
# (cp_count / cni / version 등 정적 구성은 group_vars/all.yml에서 관리)
cat > "$OUTPUT_FILE" << EOF
all:
  vars:
    install_kubernetes_control_plane_endpoint: "${CP_ENDPOINT}"
  children:
    control_plane:
      hosts:
EOF

emit_host() {
  # $1=노드 이름, $2=인스턴스 ID
  cat >> "$OUTPUT_FILE" << EOF
        $1:
          ansible_host: $2
          ansible_user: $SSH_USER
          ansible_ssh_private_key_file: $SSH_KEY
          ansible_ssh_common_args: '$SSH_COMMON'
          ansible_become: true
          ansible_become_method: sudo
          ansible_become_user: root
EOF
}

echo "$CONTROL_PLANE_IDS" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r name id; do
  emit_host "$name" "$id"
done

cat >> "$OUTPUT_FILE" << EOF
    worker_nodes:
      hosts:
EOF

echo "$WORKER_IDS" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r name id; do
  emit_host "$name" "$id"
done

echo "ha-cluster-ssm.yml 생성 완료: $OUTPUT_FILE"
echo "  control_plane_endpoint = ${CP_ENDPOINT}"
echo "  ssh_user               = ${SSH_USER}  /  region = ${REGION}"
