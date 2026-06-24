#!/bin/bash
set -e

# 스크립트 위치 기준으로 프로젝트 루트를 잡는다 (실행 위치와 무관).
cd "$(dirname "$0")/.."
BASE_DIR="$(pwd)"
INVENTORY_DIR="$BASE_DIR/inventory"

# 사용법:
#   ./run_server_spec.sh                  # 기본: inventory/hosts-sogang.yml
#   ./run_server_spec.sh hosts.yml        # 파일명만 (inventory/ 기준)
#   ./run_server_spec.sh /path/to/hosts.yml  # 절대/상대 경로도 허용
INVENTORY="${1:-hosts-sogang.yml}"

if [ -f "$INVENTORY" ]; then
  :  # 주어진 경로가 그대로 존재
elif [ -f "$INVENTORY_DIR/$INVENTORY" ]; then
  INVENTORY="$INVENTORY_DIR/$INVENTORY"  # inventory/ 기준 파일명
else
  echo "인벤토리 파일을 찾을 수 없습니다: $INVENTORY" >&2
  exit 1
fi

echo "인벤토리: $INVENTORY"
ansible-playbook -i "$INVENTORY" "$BASE_DIR/server-spec-playbook.yml"
