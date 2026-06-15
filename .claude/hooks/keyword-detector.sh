#!/usr/bin/env bash
# UserPromptSubmit hook — K8s 키워드 감지 시 적절한 skill 안내를 컨텍스트로 주입한다.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

# 클러스터 신규 구축
if echo "$PROMPT" | grep -qiE '(k8s.*(setup|구축|install|설치|만들|build)|클러스터.*(구축|만들|setup|설치)|kubernetes.*(install|설치|setup|구축)|새.*(클러스터|cluster))'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": "[K8s 클러스터 구축] /k8s-setup 스킬을 사용하면 K8s 버전(1.24+), CRI(containerd/crio), CNI(calico/flannel/cilium)를 단계별로 선택하고 Terraform → 인벤토리 → Ansible 전 파이프라인을 진행할 수 있습니다."
    }
  }'
  exit 0
fi

# 노드 추가
if echo "$PROMPT" | grep -qiE '(노드.*(추가|add|join)|node.*(add|추가|join)|worker.*(추가|add)|control.?plane.*(추가|add))'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": "[K8s 노드 추가] /k8s-node-add 스킬을 사용하면 Terraform VM 추가 → 인벤토리 갱신 → Ansible join 순서로 안전하게 진행할 수 있습니다."
    }
  }'
  exit 0
fi

# 노드 제거
if echo "$PROMPT" | grep -qiE '(노드.*(제거|삭제|remove|delete)|node.*(remove|delete|제거|삭제))'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": "[K8s 노드 제거] /k8s-node-remove 스킬을 사용하면 drain → delete → Ansible → Terraform 순서로 안전하게 진행할 수 있습니다. 파괴적 명령(kubectl drain, kubectl delete node)은 Claude가 실행할 수 없으므로 스킬의 안내에 따라 터미널에서 직접 실행하세요."
    }
  }'
  exit 0
fi

# 클러스터 상태 확인
if echo "$PROMPT" | grep -qiE '(클러스터.*(상태|확인|check|verify|health)|k8s.*(상태|확인|verify|health|check))'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": "[K8s 클러스터 검증] /k8s-verify 스킬을 사용하면 노드 상태, 시스템 Pod, etcd 헬스, CNI, HAProxy VIP를 순서대로 점검합니다."
    }
  }'
  exit 0
fi

# 새 Ansible role 생성
if echo "$PROMPT" | grep -qiE '(새.*(role|롤)|role.*(만들|생성|create|추가)|ansible.*(role|롤).*(만들|생성|create))'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": "[Ansible Role 생성] /new-role <role-name> 스킬을 사용하면 K8s 프로젝트 컨벤션에 맞는 디렉토리 구조와 기본 파일들이 생성됩니다."
    }
  }'
  exit 0
fi

exit 0
