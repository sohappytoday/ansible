# Ansible 컨벤션 및 K8s 운영 규칙

## Ansible Role 규칙

- `defaults/main.yml`에 기본값 선언, role 이름을 prefix로 사용 (예: `k8s_install_version`)
- 모든 task는 멱등성 보장 — `stat` / `command -v` / `when` 조합
- 조회성 task에 `changed_when: false` 필수
- OS 분기는 `import_tasks` 패턴:

```yaml
- import_tasks: ubuntu.yml
  when: ansible_os_family == "Debian"

- import_tasks: redhat.yml
  when: ansible_os_family == "RedHat"
```

- CRI 분기:

```yaml
- import_tasks: cri-containerd.yml
  when: cri_type == "containerd"

- import_tasks: cri-crio.yml
  when: cri_type == "crio"

- import_tasks: cri-docker.yml
  when: cri_type == "docker"
```

- CNI 분기:

```yaml
- import_tasks: cni-calico.yml
  when: cni_type == "calico"

- import_tasks: cni-flannel.yml
  when: cni_type == "flannel"

- import_tasks: cni-cilium.yml
  when: cni_type == "cilium"
```

- CP join / LB는 cp_count 조건부:

```yaml
- import_tasks: control-plane-join.yml
  when: cp_count | int >= 3

- import_tasks: lb.yml
  when: cp_count | int >= 3
```

### 파일 전송 규칙 (대용량은 scp로 통일)

- 노드 ↔ 제어노드, 노드 ↔ 노드 간 **대용량 파일(.deb 묶음, 이미지 tar 등) 전송은 `scp`로 통일한다.**
  Ansible `fetch`/`copy` 모듈은 파일을 **base64로 인코딩해 SSH 연결로 전송**하므로 느리고
  메모리 부담이 크다 (수백 MB 이미지 tar엔 부적합).
- `scp`는 shell 명령으로 호출하고 `delegate_to: localhost`로 제어노드에서 실행한다.
  인벤토리의 `ansible_ssh_private_key_file` / `ansible_user` / `ansible_host`를 그대로 사용:

```yaml
- name: Transfer image tar via scp
  shell: >
    scp -i {{ ansible_ssh_private_key_file }}
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    {{ ansible_user }}@{{ ansible_host }}:<원격경로> <로컬경로>
  delegate_to: localhost
  become: false
  changed_when: true
```

> 멱등성은 전송 전에 `stat`으로 대상 파일 존재를 확인하고 `when:`으로 건너뛰어 보장한다
> (`offline-prepare-images.yml` / `offline-prepare-packages.yml` 참고).
> 작은 설정 파일/템플릿은 기존대로 `copy`/`template` 모듈을 써도 된다.

---

## Role 디렉토리 표준 구조

```
roles/<role-name>/
├── defaults/main.yml   # 재정의 가능한 기본값
├── tasks/
│   ├── main.yml        # 진입점 (import_tasks로 분기)
│   ├── ubuntu.yml
│   └── redhat.yml
├── handlers/main.yml   # 서비스 재시작 핸들러
└── templates/          # Jinja2 템플릿
```

---

## K8s 운영 규칙

### 노드 유지보수 전 체크리스트

1. `kubectl get nodes` — 모든 노드 Ready 확인
2. `kubectl get pods -A | grep -v Running` — 비정상 Pod 없는지 확인
3. etcd 스냅샷 백업:
   ```bash
   etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db
   ```

### 업그레이드 규칙

- CP 노드 먼저 → Worker 순
- 마이너 버전 1단계씩 (예: 1.29 → 1.30, 1.31 바로 불가)
