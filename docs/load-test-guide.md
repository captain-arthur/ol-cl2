# Load 테스트 가이드

이 문서는 ClusterLoader2(CL2) **load** 테스트의 구조, 부하 조절 방법, 통과 기준 해석, 그리고 `testing/load/modules`·`testing/load/golang` 폴더 구성 요소를 정리한 것이다.

---

## 1. Load 테스트 개요

- **목적**: 다양한 오브젝트·생명주기(create / scale and update / delete) 부하 하에서 제어면(API, 스케줄러, 컨트롤러)이 정상 동작하는지 검증.
- **핵심 지표**: CreatePhase Pod Startup Latency(P99 등), Cluster OOM, Scheduler Latency, (Prometheus 사용 시) API 응답성·SLO.
- **실행 예시**:
  ```bash
  go run cmd/clusterloader.go --provider=kind --kubeconfig=$HOME/.kube/config \
    --testconfig=testing/load/config.yaml \
    --testoverrides=testing/load/ol-test.yaml \
    --report-dir=results/load --v=2
  ```

---

## 2. 부하를 높이는 방법

부하는 다음 세 가지 축으로 조절한다. **한 번에 하나씩** 올리면서 P99·실패 여부를 확인하는 것을 권장한다.

| 목적 | 파라미터 | 설명 | 부하 상향 예시 |
|------|----------|------|----------------|
| 총 파드 수 | `PODS_PER_NODE` | 노드당 파드 수. `totalPods = namespaces × NODES_PER_NAMESPACE × PODS_PER_NODE` | 30 → 50 → 80 → 100 |
| 생성/삭제 속도 | `CL2_LOAD_TEST_THROUGHPUT` | 초당 생성 파드 수(pods/s). `saturationTime = totalPods / THROUGHPUT` | 10 → 15 → 20 |
| | `CL2_DELETE_TEST_THROUGHPUT` | 초당 삭제 파드 수. 미지정 시 LOAD와 동일 | 10 → 15 → 20 |
| 컨트롤당 레플리카 | `BIG_GROUP_SIZE` | 큰 Deployment당 레플리카 수 | 8 → 16 → 24 |
| | `MEDIUM_GROUP_SIZE` | 중간 Deployment당 레플리카 수 | 1 → 2, 3 |
| | `SMALL_GROUP_SIZE` | 작은 Deployment당 레플리카 수 | 1 → 2 |

**ol-test.yaml 부하 단계 예시**

```yaml
# 1단계: 파드 수만 늘리기
PODS_PER_NODE: 50

# 2단계: 처리량도 올리기 (같은 파드 수를 더 짧은 시간에 처리)
PODS_PER_NODE: 50
CL2_LOAD_TEST_THROUGHPUT: 15
CL2_DELETE_TEST_THROUGHPUT: 15

# 3단계: 그룹 크기 키우기 (컨트롤러/API 부하 증가)
BIG_GROUP_SIZE: 16
MEDIUM_GROUP_SIZE: 2
SMALL_GROUP_SIZE: 2
```

---

## 3. 통과 기준과 “여유 있게 통과” 해석

- **CreatePhasePodStartupLatency**의 기준은 `testing/load/modules/measurements.yaml`에서 **고정 1시간**이다.  
  (P99 pod_startup &lt; 1h 이면 통과.)
- 따라서 **P99가 44초여도 “1시간보다 훨씬 여유”로만 보일 뿐**, “실제 SLO(예: 5분 이하)를 만족하는지”는 이 설정만으로는 알 수 없다.

**“여유”를 명확히 보는 방법**

1. **기준을 짧게 두고 통과/실패 보기**  
   - `measurements.yaml`의 CreatePhase Pod Startup Latency `threshold`를 파라미터화해, 예: `CL2_CREATE_PHASE_POD_STARTUP_LATENCY_THRESHOLD: 5m` 로 오버라이드하면, 5분을 넘는 P99에서 실패하여 “5분 SLO 대비 여유”를 확인할 수 있다.
2. **부하를 올리면서 P99만 관찰**  
   - threshold는 1h로 두고, 위 부하 파라미터를 단계적으로 올리며 **P99가 어디서부터 급격히 나빠지는지** 기록한다. 그 구간 아래가 “여유 있게 통과”하는 설정이다.

---

## 4. `testing/load/modules` 폴더 구성

모듈은 `testing/load/config.yaml`의 `steps`에서 `- module: path: ...` 로 불린다. 경로는 `modules/` 기준 상대경로 또는 `/modules/...` 절대형으로 적는다.

### 4.1 루트에 있는 모듈

| 파일 | 역할 |
|------|------|
| **measurements.yaml** | 테스트 전역 **측정(measurement)** 정의. start/gather 시 실행. CreatePhasePodStartupLatency(labelSelector: group=load, threshold 1h), APIResponsivenessPrometheus(Simple), ClusterOOMsTracker, TestMetrics, ResourceUsageSummary, SchedulingMetrics, SLOMeasurement, InClusterNetworkLatency, NodeLocalDNSLatency, NetworkProgrammingLatency 등 수십 개 측정의 등록·파라미터(CL2_* 등) 처리. |
| **pod-startup-latency.yaml** | **스케줄러 throughput 구간 이후**에 실행되는 **별도 Pod Startup Latency** 측정. `group=latency` 라벨의 latency 전용 Deployment를 생성·삭제하며, **labelSelector=group=latency**, **threshold=CL2_POD_STARTUP_LATENCY_THRESHOLD(기본 5s)** 로 수집. 작은 클러스터(노드&lt;100)에서는 config에서 비활성화됨. |
| **dns-k8s-hostnames.yaml** | K8s 호스트명에 대한 **DNS 성능 테스트** 실행. CL2_ENABLE_DNSTESTS 및 CL2_USE_ADVANCED_DNSTEST가 true일 때만 steps가 생성됨. |
| **dns-performance-metrics.yaml** | DNS 성능 **Prometheus 메트릭 수집** (에러율, lookup latency P50/P99 등). 위 DNS 테스트와 동일 플래그가 켜져 있을 때만 사용. |

### 4.2 configmaps-secrets/

| 파일 | 역할 |
|------|------|
| **config.yaml** | Create 단계에서 Deployment(big/medium/small) 개수만큼 **ConfigMap·Secret**을 생성. 파드 삭제 후에만 ConfigMap/Secret을 지워야 하는 이슈(kubernetes#96635) 때문에 reconcile-objects와 분리됨. |
| **configmap.yaml** | ConfigMap 템플릿. |
| **secret.yaml** | Secret 템플릿. |

### 4.3 services/

| 파일 | 역할 |
|------|------|
| **config.yaml** | 네임스페이스별 **Service** 생성/삭제. big/medium/small 서비스 개수는 config.yaml 상위에서 `smallServicesPerNamespace` 등으로 전달. |
| **service.yaml** | Service 오브젝트 템플릿. |

### 4.4 reconcile-objects/

| 파일 | 역할 |
|------|------|
| **config.yaml** | Load 테스트의 **핵심 워크로드**: create / scale and update / delete 단계에서 **Deployment, StatefulSet, DaemonSet, Job**, (옵션) NetworkPolicy, PVC 등 생성·스케일·삭제. big/medium/small 개수·레플리카 수·이미지·tuningSet·operationTimeout 등을 파라미터로 받음. |
| **deployment.yaml** | Deployment 템플릿. |
| **statefulset.yaml** | StatefulSet 템플릿. |
| **statefulset_service.yaml** | StatefulSet용 Service 템플릿. |
| **daemonset.yaml** | DaemonSet 템플릿. |
| **job.yaml** | Job 템플릿. |
| **pvc.yaml** | PVC 템플릿. |
| **networkpolicy.yaml** | NetworkPolicy 템플릿(ENABLE_NETWORKPOLICIES 시). |

### 4.5 scheduler-throughput/

| 파일 | 역할 |
|------|------|
| **config.yaml** | **스케줄러 throughput** 전용 단계. 별도 네임스페이스에 `group=scheduler-throughput` Deployment를 만들고, PodStartupLatency(threshold 1h)와 SchedulingThroughput 측정. 노드≥100이 아닌 작은 클러스터에서는 config에서 이 단계 전체가 비활성화됨. |
| **simple-deployment.yaml** | scheduler-throughput 및 pod-startup-latency에서 쓰는 단순 Deployment 템플릿(Replicas, Group, Image 등 templateFillMap). |

### 4.6 informer/

| 파일 | 역할 |
|------|------|
| **config.yaml** | **Informer 레이턴시 테스트**용 리소스 생성/삭제. informer 네임스페이스, Role, RoleBinding, 그리고 WatchList feature on/off 두 개의 Deployment 생성. CL2_ENABLE_INFORMER_LATENCY_TEST가 true일 때만 실행. |
| **namespace.yaml** | informer 전용 네임스페이스 템플릿. |
| **role.yaml** | Role 템플릿. |
| **roleBinding.yaml** | RoleBinding 템플릿. |
| **deployment.yaml** | Informer 측정용 Deployment 템플릿(EnableWatchListFeature 등). |

### 4.7 network-policy/

| 파일 | 역할 |
|------|------|
| **net-policy-enforcement-latency.yaml** | **네트워크 정책 적용 레이턴시** 측정. setup/run/complete 단계로, policy-creation·pod-creation 등 testType에 따라 정책 생성·파드 생성 시 레이턴시 측정. CL2_ENABLE_NETWORK_POLICY_ENFORCEMENT_LATENCY_TEST가 true일 때만 사용. |
| **net-policy-metrics.yaml** | 네트워크 정책 관련 **Prometheus 메트릭** 수집(PolicyCreation/PodCreation P50·P99, Cilium 메트릭 등). 위 테스트가 켜져 있을 때 gather 단계에서 호출됨. |

---

## 5. `testing/load/golang` 폴더 구성

| 파일 | 역할 |
|------|------|
| **custom_api_call_thresholds.yaml** | **API 호출별 커스텀 threshold** 정의. `CUSTOM_API_CALL_THRESHOLDS` 하나의 파라미터로, verb/resource/subresource/scope별 threshold(예: leases PUT 500ms, pods DELETE 700ms)를 YAML 블록으로 지정. `modules/measurements.yaml`의 APIResponsivenessPrometheus·APIResponsivenessPrometheusSimple 측정에서 `customThresholds`로 읽어 사용. load 테스트 오버라이드(예: `--testoverrides`)에 이 파일을 함께 넘기면, 기본 threshold 대신 이 값들이 적용된다. |

즉, **golang** 폴더는 “Go 코드”가 아니라 **오버라이드용 YAML 조각**이 들어 있는 곳이며, 현재는 API 응답성 threshold 커스터마이즈 예시 한 개만 있다.

---

## 6. 참고 링크

- Pod startup SLO: [kubernetes/community/sig-scalability/slos/pod_startup_latency.md](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/pod_startup_latency.md)
- ConfigMap/Secret 삭제 순서 이슈: [kubernetes#96635](https://github.com/kubernetes/kubernetes/issues/96635)
