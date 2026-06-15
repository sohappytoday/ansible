# S3 패키지 저장소 계획

Claude가 패키지 버전을 확인할 때 발생하는 할루시네이션 방지 및 배포 속도 향상을 위해
AWS S3를 내부 패키지 저장소로 활용한다.

## 저장 대상

- K8s 바이너리 (kubeadm, kubelet, kubectl) — 버전별
- CRI 패키지 (containerd, CRI-O)
- CNI manifest (Calico, Flannel, Cilium YAML/Helm chart)

## Ansible 연동 방식

```yaml
# 버전 존재 여부 사전 확인 — 없으면 fail (할루시네이션 방지)
- name: Verify version exists in S3
  command: aws s3 ls s3://{{ s3_bucket }}/k8s/{{ k8s_version }}/
  register: version_check
  failed_when: version_check.rc != 0

# 인터넷 대신 S3에서 다운로드
- name: Download kubectl
  get_url:
    url: "https://{{ s3_bucket }}.s3.{{ aws_region }}.amazonaws.com/k8s/{{ k8s_version }}/kubectl"
    dest: /usr/local/bin/kubectl
```

## 인벤토리 변수 (추가 예정)

```yaml
use_s3_mirror: true          # false면 공식 인터넷 저장소 사용
s3_bucket: "my-k8s-packages"
aws_region: "ap-northeast-2"
```
