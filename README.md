# Ansible

# 활용 계기

인턴 기간 동안 사내 서버와 데이터센터 서버들을 통합 모니터링할 수 있는 환경을 구축하는 업무를 맡았다.   
초기에는 각 서버에 직접 접속해 node_exporter를 설치하고 설정을 맞추는 방식으로 진행해야 했다.  

하지만 약 50개가 넘는 서버에서 이 작업을 진행해야 했기 때문에 반복성이 너무 강하다고 생각했다.    
또한 history 관리 및 작업 로그 등을 남기기가 불편하였다.  
**DevOps 엔지니어를 목표로 인턴**을 시작한 만큼, 단순 반복 작업을 그대로 수행하기보다 자동화할 수 있는 방법을 고민했다.  

또한 **인턴 기간이 끝난 뒤에도 사내에서 실제로 사용할 수 있는 결과물**을 남기고 싶었다.  
그래서 여러 서버에 비슷한 설치,설정 작업을 일관되게 적용할 수 있는 IaC 자동화 툴을 찾아보게 되었다.  

CNCF 검색, ChatGPT 검색 등 여러가지를 알아보면서 RedHat이 개발한 오픈소스 IT 자동화 도구인 Ansible을 이용해보게 되었다.  

---
# 작업내용

`추가 작업`으로 표시한 항목은 기존 요청 범위를 넘어, 모니터링 환경을 더 개선해보고자 직접 구현한 뒤 사수분께 공유드린 내용입니다.  
`추가 공부`으로 표시한 항목은 회사랑 관련 없이, 제가 편할려고 만든 작업 내용입니다.

- [Node Exporter 설치](#Node-Exporter-설치)
- [모든 서버 사양 조사 (`추가 작업`)](#모든-서버-사양-조사)
- [Database로 우회하여 GPU 및 프로세스 상태 변화 수집 (`추가 작업`)](#Database로-우회하여-GPU-및-프로세스-상태-변화-수집)
- [Docker 설치 (`추가 공부`)](#Docker-설치)  
- [Kubernetes 설치 (`추가 공부`)](#Kubernetes-설치)  

## Node Exporter 설치

### Node Exporter란?

Node Exporter는 Prometheus 생태계의 공식 익스포터로, Linux/Unix 서버의 **하드웨어 및 OS 수준 메트릭**을 수집해 Prometheus가 스크랩할 수 있는 형태로 노출한다.

주요 수집 항목은 다음과 같다.

| 항목 | 설명 |
|---|---|
| CPU | 코어별 사용률, idle/iowait/user/system 시간 |
| Memory | 총 메모리, 사용 중, 캐시, 버퍼, 스왑 등 |
| Network | 인터페이스별 송수신 바이트, 패킷, 에러 |

기본 포트는 `9100`이지만, 이 프로젝트에서는 여러 서버에서 포트를 통일하기 위해 사용하지 않는 포트 중 하나인 **`30910`**으로 변경해 운영했다.

---

### 설계 방식

#### 전체 흐름

```
Ansible 제어 노드 (로컬)
    │
    ├─ 1. GitHub에서 node_exporter 바이너리 다운로드 (로컬 /tmp에 캐싱)
    │
    └─ 2. 각 대상 서버로 업로드 → 압축 해제 → 바이너리 배치
               │
               ├─ 3. 전용 시스템 유저(node_exporter) 생성
               ├─ 4. systemd 서비스 등록 및 활성화
               ├─ 5. 방화벽(firewalld / ufw) 중지
               └─ 6. /tmp 임시 파일 정리
```

#### 주요 설계 포인트

**1. 바이너리 로컬 캐싱 (`delegate_to: localhost`)**

50개 이상의 서버에 동일 파일을 배포할 때, 서버마다 GitHub에서 직접 다운로드하면 네트워크 부하가 심하고 속도도 느리다.
아카이브가 로컬 `/tmp`에 없을 때만 한 번 다운로드하고, 이후 서버들에는 `copy` 모듈로 업로드하는 방식을 사용했다.

```yaml
- name: Check node_exporter archive exists
  stat:
    path: "/tmp/node_exporter-{{ node_exporter_version }}.linux-{{ arch }}.tar.gz"
  register: node_exporter_archive
  delegate_to: localhost

- name: Download node_exporter
  get_url:
    url: "https://github.com/prometheus/node_exporter/releases/download/..."
    dest: "/tmp/node_exporter-{{ node_exporter_version }}.linux-{{ arch }}.tar.gz"
  when: not node_exporter_archive.stat.exists
  delegate_to: localhost
```

**2. amd64 / arm64 자동 감지**

사내에 x86 서버와 ARM 서버가 혼재해 있어, `ansible_architecture` 팩트를 활용해 아키텍처를 자동으로 판별했다.

```yaml
- name: Check architecture
  set_fact:
    arch: "{{ 'arm64' if ansible_architecture == 'aarch64' else 'amd64' }}"
```

**3. 전용 시스템 유저 + systemd 보안 강화**

node_exporter 프로세스가 불필요한 권한을 갖지 않도록 로그인 불가 시스템 유저를 생성하고, systemd 유닛에 보안 옵션을 적용했다.

```ini
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
PrivateTmp=true
PrivateDevices=true
RestrictSUIDSGID=true
```

**4. OS 계열별 방화벽 처리**

Rocky Linux / RHEL 계열은 `firewalld`와 SELinux를, Ubuntu / Debian 계열은 `ufw`를 중지하도록 분기했다.

```yaml
- name: Stop firewalld (Rocky/RHEL 계열만)
  systemd:
    name: firewalld
    state: stopped
  when: ansible_os_family == "RedHat"

- name: Stop ufw (Ubuntu/Debian 계열만)
  systemd:
    name: ufw
    state: stopped
  when: ansible_os_family == "Debian"
```

**5. 불필요한 마운트 포인트 제외**

`/proc`, `/sys`, Docker/컨테이너 관련 overlay 파일시스템 등은 메트릭 노이즈가 심하기 때문에 수집 대상에서 제외했다.

---

### 롤 구조

```
roles/node_exporter/
├── defaults/
│   └── main.yml          # 버전, 포트, 유저명 기본값
├── handlers/
│   └── main.yml          # systemd 재시작 핸들러
├── tasks/
│   └── main.yml          # 설치 태스크 전체
└── templates/
    └── node-exporter.service.j2   # systemd 유닛 템플릿
```

변수는 `defaults/main.yml`에서 관리하므로, 포트나 버전 변경 시 해당 파일만 수정하면 된다.

```yaml
node_exporter_version: "1.8.2"
node_exporter_port: 30910
node_exporter_user: node_exporter
```

---

### 실행 방법

```bash
ansible-playbook -i inventory/hosts.yml install-node-exporter-playbook.yml
```

---

### Grafana 대시보드 결과

![전체 서버 기본 현황](images/node-exporter/total-default.png)

![전체 서버 Top 5](images/node-exporter/total-top5.png)

![CPU/메모리 Top 10](images/node-exporter/cpu-mem-top10.png)

![네트워크 Top 10](images/node-exporter/network-top10.png)

---

## 모든 서버 사양 조사

### 개요

Node Exporter 설치 작업과 병행해 약 50개 서버의 하드웨어 사양을 한눈에 파악할 수 있는 문서가 필요했다.  
각 서버에 직접 접속해 `lscpu`, `free`, `lsblk` 등을 실행하고 결과를 수작업으로 정리하는 것은 비효율적이라고 판단했다.  
그래서 Ansible로 모든 서버의 사양을 일괄 수집하고, **Excel 파일로 자동 생성**하는 작업을 구현했다.

---

### 설계 방식

#### 전체 흐름

```
Ansible 제어 노드 (로컬)
    │
    ├─ [Play 1] 각 대상 서버에서 사양 수집
    │       ├─ 내부 IP, Hostname, OS
    │       ├─ CPU 모델명, 코어 수, 스레드/코어
    │       ├─ RAM 용량
    │       └─ Disk 목록 (이름, 타입, 크기, 모델)
    │
    ├─ 수집 결과를 로컬 output/json/ 에 호스트별 JSON으로 저장
    │       └─ 파일명: {inventory_hostname}_{수집시각}.json
    │
    └─ [Play 2] 로컬에서 Docker로 Excel 생성
            ├─ Python(openpyxl) 이미지 빌드
            ├─ JSON 파일들을 읽어 .xlsx 생성 → output/xlsx/
            └─ 임시 Docker 이미지 및 JSON 파일 정리
```

#### 주요 설계 포인트

**1. JSON 로컬 저장**

각 서버에서 수집한 사양 데이터를 원격 서버가 아닌 Ansible 제어 노드(로컬)에 저장해야 했다.  
`delegate_to: localhost`를 사용해 `copy` 모듈을 로컬에서 실행함으로써, 서버별 결과를 로컬에 JSON으로 축적했다.

```yaml
- name: Save server info as JSON
  copy:
    content: "{{ server_info | to_nice_json }}"
    dest: "./output/json/{{ inventory_hostname }}_{{ hostvars['localhost']['collected_time'] }}.json"
  delegate_to: localhost
```

**~~2. 내부 IP prefix 필터링~~** (2-1 버전으로 업그레이드 되었습니다.)

서버에는 인터넷 IP, 내부망 IP 등 여러 IP가 할당된 경우가 많다.  
`hostname -I`의 출력 중 사내 내부망 대역(`192.`)에 해당하는 IP만 추출하도록 `internal_ip_prefix` 변수로 분리했다.

```yaml
- name: Get Internal IP
  shell: hostname -I | tr ' ' '\n' | grep '^{{ internal_ip_prefix }}' | head -n 1
```

```yaml
# defaults/main.yml
internal_ip_prefix: "192."
```

**2-1. 자체 피드백** (완료)

- 기존 방식의 한계점  
지금 한 방식은 내부 IP가 192로 시작해야 한다라는 조건이 있지만, `172`나 복합적으로 사용하게 되면 찾을 수 없다는 한계점이 있다.  
또한 내부 IP만 잡아내고 있다는 단점이 있었다.

- External IP   
따라서, 외부 IP의 경우 지금 접속해있는 IP의 공인 IP를 던져주는 `ifconfig.me`라는 사이트가 존재한다.  
이를 통해 `curl -4 ifconfig.me`를 하면 외부 IP를 Prefix없이 가져올 수 있다.

- Internal IP  
내부 IP의 경우 외부 인터넷로 나갈 때 어떤 내부 IP를 사용하는지 확인하면 될 것 같다. 
`ip route get 8.8.8.8`을 했을 때 결과가 `8.8.8.8 via <gateway> dev ens5 src <internal ip> uid 0` 이런식으로 나올 수 있다. 
따라서 7번째 결과로 Internal IP를 뽑을 수 있고, 추가적으로 3번째 결과로 gateway까지 뽑아낼 수 있다.  
Internal IP : `ip route get 8.8.8.8 | awk {print $7}`  
Gateway : `ip route get 8.8.8.8 | awk {print $3}`

**3. 2-Play 구조로 수집과 Excel 생성 분리**

하나의 플레이북 안에서 역할을 명확히 분리했다.  
첫 번째 Play는 `hosts: all`로 모든 서버를 대상으로 사양을 수집하고, 두 번째 Play는 `hosts: localhost`로 수집된 JSON을 기반으로 Excel을 생성한다.

```yaml
- name: Get Server Spec        # Play 1: 전체 서버 수집
  hosts: all
  roles:
    - server_spec

- name: Generate Server Spec Excel  # Play 2: 로컬에서 Excel 생성
  hosts: localhost
  gather_facts: false
  roles:
    - server_spec_excel
```

**4. Docker 기반 Excel 변환**

Excel 생성은 이 플레이북에서만 필요한 일회성 작업이다.  
`openpyxl` 같은 Python 패키지를 제어 노드에 직접 설치하면, 이후 사용하지 않을 패키지가 서버에 계속 남게 된다.  
Docker 컨테이너로 실행 환경을 격리하면 서버를 오염시키지 않고, 실행 후 이미지를 즉시 삭제해 흔적도 남지 않는다.

```yaml
- name: Build Excel generator Docker image
  command: docker build -f server_spec.Dockerfile -t {{ excel_image_name }}:{{ excel_image_version }} .

- name: Generate Excel from JSON files
  command: docker run --rm -v {{ playbook_dir }}/output:/app {{ excel_image_name }}:{{ excel_image_version }}

- name: Remove Docker image
  command: docker rmi {{ excel_image_name }}:{{ excel_image_version }}
```

**5. 수집 완료 후 JSON 정리**

Excel 생성이 끝난 뒤 중간 산출물인 JSON 파일들을 `find` 모듈로 탐색 후 삭제한다.  
`output/xlsx/`에는 Excel만 남고 JSON은 자동으로 제거된다.

---

### 롤 구조

```
roles/
├── server_spec/
│   ├── defaults/
│   │   └── main.yml          # 내부 IP prefix 기본값
│   └── tasks/
│       └── main.yml          # 사양 수집 태스크 전체
│
└── server_spec_excel/
    ├── defaults/
    │   └── main.yml          # Docker 이미지명/버전
    ├── files/
    │   ├── make_server_spec_excel.py   # JSON → Excel 변환 스크립트
    │   └── server_spec.Dockerfile      # Python + openpyxl 이미지
    └── tasks/
        └── main.yml          # Docker 빌드 → 실행 → 정리
```

---

### 실행 방법

```bash
ansible-playbook -i inventory/hosts.yml server-spec-playbook.yml
```

또는 셸 스크립트로 실행:

```bash
./shell/run_server_spec.sh
```

실행이 완료되면 `output/xlsx/server-spec-{날짜}.xlsx` 파일이 생성된다.

---

### Excel 결과

| 컬럼 | 설명 |
|---|---|
| Server | 인벤토리 호스트명 |
| Hostname | 서버 실제 hostname |
| Internal IP | 외부 인터넷으로 나가는 내부 IP |
| External IP | 공인 IP |
| Gateway | 게이트웨이 IP |
| OS | OS 이름 및 버전 |
| CPU Model | CPU 모델명 |
| CPU Core Count | 전체 코어 수 |
| CPU Thread/Core | 코어당 스레드 수 |
| RAM | 총 메모리 용량 |
| Disk | 디스크 목록 (이름/타입/크기/모델) |

---
# 트러블 슈팅


---
# 추가 작업 진행해볼 것
