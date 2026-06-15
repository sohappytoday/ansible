#!/usr/bin/env bash
# PreToolUse hook (Bash) — K8s/Terraform 파괴적 명령을 완전 차단한다.
# 차단된 명령은 사용자가 터미널에서 직접 실행해야 한다.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
}

# kubeadm reset — 클러스터 노드 파괴
if echo "$COMMAND" | grep -qE 'kubeadm\s+reset'; then
  deny "kubeadm reset은 클러스터 노드를 파괴합니다. 반드시 터미널에서 직접 실행하세요: kubeadm reset"
fi

# terraform destroy — 모든 VM 삭제
if echo "$COMMAND" | grep -qE 'terraform\s+(destroy|-destroy)'; then
  deny "terraform destroy는 모든 VM을 삭제합니다. 반드시 터미널에서 직접 실행하세요: terraform destroy"
fi

# kubectl drain — 노드 워크로드 이동 (서비스 중단 가능)
if echo "$COMMAND" | grep -qE 'kubectl\s+drain'; then
  deny "kubectl drain은 서비스 중단을 유발할 수 있습니다. /k8s-node-remove 스킬의 안내에 따라 터미널에서 직접 실행하세요."
fi

# kubectl delete node — 노드 오브젝트 삭제
if echo "$COMMAND" | grep -qE 'kubectl\s+delete\s+node'; then
  deny "kubectl delete node는 클러스터에서 노드를 제거합니다. /k8s-node-remove 스킬의 안내에 따라 터미널에서 직접 실행하세요."
fi

# etcdctl member remove — etcd 멤버 제거
if echo "$COMMAND" | grep -qE 'etcdctl\s+member\s+remove'; then
  deny "etcdctl member remove는 etcd 쿼럼을 변경합니다. 반드시 터미널에서 직접 실행하세요."
fi

# etcdctl del / delete — etcd 키 직접 삭제
if echo "$COMMAND" | grep -qE 'etcdctl\s+(del|delete)\s'; then
  deny "etcdctl del/delete는 etcd 데이터를 직접 삭제합니다. 데이터 손실 위험이 있으므로 반드시 터미널에서 직접 실행하세요."
fi

exit 0
