# Density 테스트

density 시나리오 설정 및 로컬(Kind) 환경에서의 실행 안내.

## 설정 요약 (ol-test.yaml)

- **Saturation**: 파드 수 = 노드 수 × `PODS_PER_NODE`  
  SLI/SLO: `ol-test.yaml` 주석 참고.
- **Latency**: 파드 수 = `MIN_LATENCY_PODS`  
  SLI/SLO: `ol-test.yaml` 주석 참고.

## Kind 환경에서 TestMetrics(SchedulingMetrics) 사용하기

density 테스트의 **TestMetrics**는 스케줄러 메트릭을 **API server Pod proxy**로 가져옵니다.  
Kind에서는 kube-scheduler가 기본값으로 **`--bind-address=127.0.0.1`** 이라 Pod IP로 접근이 안 되어 **503**이 나고, TestMetrics가 실패할 수 있습니다.

**지금 사용 중인 클러스터의 control-plane 컨테이너**에서만 아래 작업을 해야 합니다.  
다른 클러스터 컨테이너를 수정하면 CL2 테스트에는 반영되지 않습니다.

### 1. 컨테이너 이름 확인 (필수)

`docker ps`로 **control-plane 컨테이너**를 확인합니다.  
여러 클러스터가 있으면 이름이 여러 개 보입니다.

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}' | grep -E "control-plane|NAMES"
```

예시 출력 (Kind 두 개 + 기타):

| NAMES                       | IMAGE                |
|-----------------------------|----------------------|
| desktop-control-plane       | kindest/node:v1.25.16  |
| test-cluster-control-plane  | kindest/node:v1.35.0   |

- **지금 kubectl/CL2가 쓰는 클러스터**의 control-plane만 수정해야 합니다.
- `kubectl get nodes` 의 **control-plane 노드 이름** = 수정할 **컨테이너 이름**과 같습니다.

```bash
# 현재 context의 control-plane 노드 이름 확인 (= 수정할 컨테이너 이름)
kubectl get nodes
# 예: desktop-control-plane 가 보이면 → 컨테이너 이름은 desktop-control-plane
```

### 2. Kind control-plane 컨테이너 이름 규칙

| 클러스터 생성 예시 | control-plane 컨테이너 이름 |
|--------------------|-----------------------------|
| `kind create cluster` | `kind-control-plane` |
| `kind create cluster --name desktop` | `desktop-control-plane` |
| `kind create cluster --name test-cluster` | `test-cluster-control-plane` |

규칙: **`<클러스터이름>-control-plane`** (이름 생략 시 `kind`).

### 3. 스케줄러 bind-address를 0.0.0.0으로 변경

**CONTAINER_NAME**을 1번에서 확인한 **현재 사용 중인** control-plane 컨테이너 이름으로 바꿉니다.  
(예: desktop 쓰는 중이면 `desktop-control-plane`)

```bash
docker exec CONTAINER_NAME sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-scheduler.yaml
```

### 4. 스케줄러 /metrics 경로 인증 예외 추가 (403 방지)

API server Pod proxy로 스케줄러에 접근하면 스케줄러는 클라이언트를 `system:anonymous`로 보며, 기본 설정에서는 `/metrics` 접근이 403 Forbidden 됩니다.  
아래 한 줄을 추가해 `/metrics`를 인증 없이 허용합니다.

```bash
docker exec CONTAINER_NAME sed -i '/--authorization-kubeconfig=\/etc\/kubernetes\/scheduler.conf/a\    - --authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics' /etc/kubernetes/manifests/kube-scheduler.yaml
```

확인:

```bash
docker exec CONTAINER_NAME grep -A1 "authorization-kubeconfig" /etc/kubernetes/manifests/kube-scheduler.yaml
# 출력에 다음 줄이 있어야 함:     - --authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics
```

저장만 하면 kubelet이 매니페스트 변경을 감지해 스케줄러 Pod를 자동 재시작합니다.

### 5. 클러스터 재생성 후에도 유지하려면 (Kind 설정)

`kind delete cluster` 후 다시 만들면 위 수정은 사라집니다.  
영구 반영하려면 Kind 설정 파일에 `kubeadmConfigPatches`를 넣습니다.

예시 `kind-config.yaml` (bind-address + /metrics 허용):

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatches:
- |
  kind: ClusterConfiguration
  apiVersion: kubeadm.k8s.io/v1beta4
  scheduler:
    extraArgs:
      bind-address: "0.0.0.0"
      authorization-always-allow-paths: "/healthz,/readyz,/livez,/metrics"
```

클러스터 생성:

```bash
kind create cluster --name desktop --config kind-config.yaml
```

### 6. 주의 (보안)

- `0.0.0.0`으로 바인딩하면 스케줄러 메트릭(10259)이 **클러스터 내에서** 해당 노드 IP로 접근 가능해집니다.
- **로컬/개발용** Kind에서는 보통 괜찮습니다.
- **프로덕션**에서는 방화벽·NetworkPolicy 등으로 10259 접근을 제한하는 것이 좋습니다.

## 온프레/일반 클러스터에서 TestMetrics(SchedulingMetrics) 사용하기

온프레미스/일반적인 Kubernetes 클러스터(예: kubeadm 기반)에서도 해결해야 하는 문제는 **Kind와 동일**합니다.

- kube-scheduler의 secure 포트(기본 10259)가 **`127.0.0.1`** 에만 바인딩되어 있으면, API server Pod proxy가 스케줄러 Pod IP:10259로 연결할 수 없습니다.
- 스케줄러는 `/metrics` 요청을 기본적으로 인증·인가 대상으로 보기 때문에, Pod proxy를 통해 접근하면 클라이언트를 `system:anonymous`로 인식하고 403 Forbidden 을 반환할 수 있습니다.

따라서 두 가지를 만족해야 합니다.

1. kube-scheduler가 **`0.0.0.0:10259`** 로 리스닝할 것 (`--bind-address=0.0.0.0`)
2. 스케줄러 프로세스가 **`/metrics` 경로를 인증 없이 허용**할 것 (`--authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics`)

아래는 kubeadm 기반 **static Pod** 와, Deployment 로 실행되는 두 경우에 대한 예시입니다.

### 1. kube-scheduler 실행 방식 확인

- **Pod 목록 확인**

```bash
kubectl -n kube-system get pods -l component=kube-scheduler -o wide
```

- **Deployment 여부 확인**

```bash
kubectl -n kube-system get deploy kube-scheduler
```

- `kube-scheduler` Deployment가 **없고**, control-plane 노드에 `kube-scheduler-<노드이름>` Pod만 있다면  
  → kubeadm 기본값처럼 **static Pod (`/etc/kubernetes/manifests/kube-scheduler.yaml`)** 로 실행 중일 가능성이 높습니다.
- `kube-scheduler` Deployment가 존재하면  
  → Deployment 의 `spec.template.spec.containers[0].args` 를 수정해야 합니다.

### 2-A. kubeadm 기반 static Pod 환경 (가장 흔한 온프레)

1. **control-plane 노드 이름 확인**

```bash
kubectl get nodes
```

2. 해당 노드에 SSH 접속 (예시)

```bash
ssh root@<CONTROL_PLANE_NODE>
```

3. `kube-scheduler` 매니페스트 편집

- 파일 경로(기본값): `/etc/kubernetes/manifests/kube-scheduler.yaml`
- `containers[0].command` 또는 `containers[0].args` 아래 인자를 다음과 같이 맞춥니다.

```yaml
  - kube-scheduler
  - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
  - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
  - --bind-address=0.0.0.0
  - --kubeconfig=/etc/kubernetes/scheduler.conf
  - --leader-elect=true
  - --authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics
```

- 이미 `--bind-address=0.0.0.0` 가 있다면 그대로 두고,  
  `--authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics` 가 없다면 인자로 추가합니다.

4. 파일 저장 후 대기

- `/etc/kubernetes/manifests/kube-scheduler.yaml` 를 저장하면, kubelet 이 변경을 감지해 **스케줄러 Pod를 자동 재생성**합니다.
- `kubectl -n kube-system get pods -l component=kube-scheduler` 로 새 Pod 가 Running 인지 확인합니다.

### 2-B. Deployment 로 실행되는 kube-scheduler 환경

1. Deployment 편집

```bash
kubectl -n kube-system edit deploy kube-scheduler
```

2. `spec.template.spec.containers[0].args` 아래에 다음 인자를 포함시킵니다.

```yaml
    - --bind-address=0.0.0.0
    - --authorization-always-allow-paths=/healthz,/readyz,/livez,/metrics
```

- `--bind-address` 가 이미 존재한다면 값을 `0.0.0.0` 으로 변경합니다.
- `--authorization-always-allow-paths` 가 이미 있다면 `/metrics` 가 포함되도록 값을 수정합니다.

3. 저장 후 롤아웃 상태 확인

```bash
kubectl -n kube-system rollout status deploy kube-scheduler
```

롤아웃이 완료되면, CL2의 **TestMetrics(SchedulingMetrics)** 는 Kind 와 동일하게  
API server Pod proxy 경로를 통해 kube-scheduler `/metrics` 에 접근할 수 있어야 합니다.
