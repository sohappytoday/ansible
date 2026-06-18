#!/bin/bash
# terraform output을 읽어 cluster-hosts.yml을 생성한다.
# 실행 전에 terraform apply가 완료되어 있어야 한다.

TERRAFORM_DIR="/home/ubuntu/terraform/templates"
OUTPUT_FILE="$(cd "$(dirname "$0")" && pwd)/cluster-hosts.yml"
SSH_KEY="~/.ssh/terraform-key"

cd "$TERRAFORM_DIR" || { echo "terraform 디렉토리를 찾을 수 없습니다: $TERRAFORM_DIR"; exit 1; }

CONTROL_PLANE_IP=$(terraform output -raw control_plane_public_ip 2>/dev/null)
if [ -z "$CONTROL_PLANE_IP" ]; then
  echo "control_plane_public_ip를 가져올 수 없습니다. terraform apply가 완료됐는지 확인하세요."
  exit 1
fi

WORKER_PRIVATE_IPS=$(terraform output -json worker_node_private_ips 2>/dev/null)
if [ -z "$WORKER_PRIVATE_IPS" ] || [ "$WORKER_PRIVATE_IPS" = "{}" ]; then
  echo "worker_node_private_ips를 가져올 수 없습니다."
  exit 1
fi

SSH_USER=$(terraform output -raw ssh_user 2>/dev/null)
if [ -z "$SSH_USER" ]; then
  echo "ssh_user를 가져올 수 없습니다."
  exit 1
fi

cat > "$OUTPUT_FILE" << EOF
all:
  children:
    control_plane:
      hosts:
        master-1:
          ansible_host: $CONTROL_PLANE_IP
          ansible_port: 22
          ansible_user: $SSH_USER
          ansible_ssh_private_key_file: $SSH_KEY
          ansible_become: true
          ansible_become_method: sudo
          ansible_become_user: root
    worker_nodes:
      hosts:
EOF

echo "$WORKER_PRIVATE_IPS" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r name ip; do
  cat >> "$OUTPUT_FILE" << EOF
        $name:
          ansible_host: $ip
          ansible_port: 22
          ansible_user: $SSH_USER
          ansible_ssh_private_key_file: $SSH_KEY
          ansible_become: true
          ansible_become_method: sudo
          ansible_become_user: root
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -i $SSH_KEY -W %h:%p -q -o StrictHostKeyChecking=no $SSH_USER@$CONTROL_PLANE_IP"'
EOF
done

echo "cluster-hosts.yml 생성 완료: $OUTPUT_FILE"
