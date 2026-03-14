# Load 테스트 기반 클러스터 인수 테스트 리포트

## 1. 목적

- Load 테스트 시나리오를 실행하여 **다양한 지표를 검증**하고, **클러스터 인수 테스트의 기준**을 마련한다.
- 기준은 Kubernetes 공식 SLO 및 ClusterLoader2(CL2) 기본 임계치를 참고하며, 우리 클러스터 규모에 맞게 조정한다.
- 지표는 **비전문가 관리자·사용자**가 이해할 수 있고, **사용자 관점에서 유의미한 정보**가 되도록 정리한다.

---

## 2. 사용자 관점에서의 지표 해석

각 지표마다 **CL2 기본값**, **CL2가 SLO로 채택한 이유**, **우리 테스트 결과**, **결과 해석**, **우리 SLO 제안·결정 방법**을 정리했다.

---

### 2.1 Pod 시작 지연 (PodStartupLatency)

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "파드를 만들었을 때 얼마나 빨리 Running이 되는가" |
| **CL2 기본값** | **5s** (코드: `defaultPodStartupLatencyThreshold = 5 * time.Second`) |
| **CL2가 SLO로 쓴 이유** | Kubernetes 공식 [Pod Startup Latency SLO](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/pod_startup_latency.md): "이미지가 이미 노드에 있는 경우" P99 ≤ 5s. 대규모 클러스터에서도 사용자 체감 품질을 보장하기 위한 업스트림 합의값. |
| **우리 테스트 결과** | CreatePhase **pod_startup** P50 7.47s, P90 13.67s, **P99 16.11s** |
| **왜 이런 결과가 나왔는가** | kind 3노드·로컬 환경에서 이미지 풀(pause 등), 스케줄링·컨테이너 시작 지연이 누적됨. 공식 SLO는 "이미지가 노드에 있을 때"를 전제하므로, 첫 풀·리소스 제약이 있으면 5s를 넘기 쉬움. |
| **우리 SLO 제안·결정 방법** | (1) **우선 5s 유지**하고, 이미지 프리로드·리소스 여유를 둔 뒤 재측정. (2) 환경이 한계라면 **P99 15s** 수준으로 완화(본 run 16.1s 근처). (3) **방법론**: N회 실행의 P99 중앙값 또는 90% 구간을 구한 뒤, "이 환경의 상한"으로 SLO를 두고, 개선 시 5s로 단계적 강화. |

---

### 2.2 API 응답 지연 (APIResponsivenessPrometheus)

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "kubectl / API 호출이 얼마나 빨리 응답하는가" |
| **CL2 기본값** | **단일 리소스(scope=resource) P99 ≤ 1s**, **LIST 등(scope≠resource) P99 ≤ 30s** (코드: `singleResourceThreshold`, `multipleResourcesThreshold`). Kubernetes 문서상 namespace LIST는 5s 권장. |
| **CL2가 SLO로 쓴 이유** | Kubernetes 공식 [API Call Latency SLO](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/api_call_latency.md): GET/PUT 등 단일 리소스 1s, LIST는 데이터량에 따라 5s/30s. 대규모에서도 API가 "느리지 않다"는 체감을 보장. |
| **우리 테스트 결과** | **미측정** (Prometheus 비활성으로 스킵). |
| **왜 이런 결과가 나왔는가** | 본회 실행에서 Prometheus 미기동으로 API 지연 수집이 비활성화됨. |
| **우리 SLO 제안·결정 방법** | (1) **기본은 업스트림과 동일**: 단일 1s, LIST 30s(또는 namespace 5s). (2) Prometheus 켠 뒤 N회 측정해 P99 분포를 보고, 초과가 반복되면 해당 verb/resource만 커스텀 임계치(`CUSTOM_API_CALL_THRESHOLDS`)로 완화하고 **이유(예: 클러스터 크기, 네트워크)**를 기록. (3) **방법론**: "대부분의 호출이 기준 이내"가 목표이므로, allowedSlowCalls를 0으로 두고, 필요 시 소수만 예외로 두는 방식. |

---

### 2.3 네트워크 프로그래밍 지연 (NetworkProgrammingLatency)

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "서비스/엔드포인트 변경이 노드에 얼마나 빨리 반영되는가" (트래픽이 새 백엔드로 가기까지) |
| **CL2 기본값** | **30s** (measurements.yaml: `CL2_NETWORK_PROGRAMMING_LATENCY_THRESHOLD` 기본 "30s"). 코드에는 기본값 없고 설정에서 필수. |
| **CL2가 SLO로 쓴 이유** | Kubernetes 공식 [Network Programming Latency SLO](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/network_programming_latency.md): 서비스/엔드포인트 변경이 모든 노드의 kube-proxy에 반영되기까지 P99 30s 이하. 사용자 트래픽이 새 파드로 전환되는 “최대 지연”에 해당. |
| **우리 테스트 결과** | **미측정** (Prometheus 비활성으로 스킵). |
| **왜 이런 결과가 나왔는가** | Prometheus 미기동 + (Prometheus를 켰을 때는) kube-proxy 메트릭/레코딩 룰이 없거나 0 샘플이면 미측정. |
| **우리 SLO 제안·결정 방법** | (1) **기본 30s 유지**. (2) Prometheus·kube-proxy 스크랩·레코딩 룰 확인 후 재측정. (3) **방법론**: 측정값이 30s 근처면 그대로 채택; 소규모 클러스터에서 안정적으로 10s 이하가 나오면 "우리 환경은 15s"처럼 여유 있게 두고, 나중에 30s로 강화. |

---

### 2.4 클러스터 내 네트워크 지연 (InClusterNetworkLatency)

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "파드 간 통신이 얼마나 빠른가" (RTT 등) |
| **CL2 기본값** | **0s** (violation 비활성). `CL2_NETWORK_LATENCY_THRESHOLD` 기본 "0s" → 위반 검사 없이 지표만 수집. |
| **CL2가 SLO로 쓴 이유** | 공식 SLO 문서에 “클러스터 내 RTT N ms 이하” 같은 단일 수치는 없음. CL2는 프로브 기반으로 지표를 모으고, 임계치는 사용자가 설정. |
| **우리 테스트 결과** | **미측정** (Prometheus 비활성). |
| **왜 이런 결과가 나왔는가** | Prometheus 미기동으로 프로브 결과 집계가 스킵됨. |
| **우리 SLO 제안·결정 방법** | (1) 먼저 **0s로 두고 수집만** 한 뒤, P50/P99 분포(예: 수 ms~수십 ms)를 본다. (2) “평상시 N ms 이하”를 목표로 두고 싶으면 **P99를 N ms로 두고 threshold를 "N ms"로 설정**한 뒤, violation 활성화. (3) **방법론**: 동일 토폴로지에서 여러 번 측정한 P99의 상한을 “이 환경의 SLO”로 정하고, 네트워크 변경 시마다 재측정. |

---

### 2.5 스케줄러 처리량 (SchedulingThroughput)

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "한 번에 많은 파드를 띄울 때 초당 몇 개까지 스케줄되는가" |
| **CL2 기본값** | **100 pods/s** (`CL2_SCHEDULER_THROUGHPUT_THRESHOLD` 기본 100). |
| **CL2가 SLO로 쓴 이유** | 대규모 클러스터(수백~수천 노드)에서 대량 배포 시 스케줄러가 병목이 되지 않도록 “최소 처리량”을 두기 위함. 100은 업스트림/대규모 테스트에서 쓰이는 참고치. |
| **우리 테스트 결과** | **미측정** (본 run에서는 스케줄러 처리량 전용 단계 결과 미기록. SchedulingMetrics는 kind pod proxy 이슈로 실패). |
| **왜 이런 결과가 나왔는가** | 스케줄러 메트릭 수집이 TestMetrics(SchedulingMetrics) 실패로 불완전. 소규모(3노드)에서는 100 pods/s에 미달해도 자연스러울 수 있음. |
| **우리 SLO 제안·결정 방법** | (1) **노드 수에 비례해 완화**: 예) 노드 3이면 100 대신 **10~30 pods/s**를 “이 클러스터의 목표”로 두고, N회 측정 평균/중앙값이 그 이상이면 통과. (2) **방법론**: “(노드 수 × K) pods/s” 형태로 K를 정하고(예: K=5~10), 한 번에 많은 파드를 만드는 시나리오로 여러 번 돌려서 채택. |

---

### 2.6 API 가용성 (APIAvailability)

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "테스트 동안 API가 얼마나 끊기지 않고 응답했는가" |
| **CL2 기본값** | **99.5%** (`CL2_API_AVAILABILITY_PERCENTAGE_THRESHOLD`). 측정은 `CL2_ENABLE_API_AVAILABILITY_MEASUREMENT: true` 일 때만 수행. |
| **CL2가 SLO로 쓴 이유** | “거의 항상 API를 쓸 수 있다”는 가용성 목표. 99.5%면 월 기준 약 3.6시간 미만 다운 허용 수준. |
| **우리 테스트 결과** | **미측정** (API 가용성 측정 비활성). |
| **왜 이런 결과가 나왔는가** | 기본이 비활성이라 본 run에서 수집하지 않음. |
| **우리 SLO 제안·결정 방법** | (1) **99.5% 유지** 권장. (2) 측정 활성화 후, 짧은 테스트(수 분)에서는 100%에 가깝게 나오는지 확인. (3) **방법론**: 테스트 길이를 늘리면서 “N분 동안 99.5% 이상”을 조건으로 두고, 미달 시 원인(노드/API 재시작 등) 조사 후 재측정. |

---

### 2.7 시스템 파드 / 재시작 / OOM

| 항목 | 내용 |
|------|------|
| **사용자에게 의미** | "컨트롤 플레인·시스템이 안정적인가" (재시작·OOM 없음) |
| **CL2 기본값** | **재시작 0회**(시스템 파드), **OOM 0건**. 코드/설정에서 “허용 재시작 수” 등을 오버라이드 가능. |
| **CL2가 SLO로 쓴 이유** | 인수 테스트 기간 동안 컨트롤 플레인·시스템 컴포넌트가 비정상 종료·OOM 없이 동작하는지 확인하기 위함. |
| **우리 테스트 결과** | **ClusterOOMsTracker**: OOM **0건**. **SystemPodMetrics**: 시스템 파드 **재시작 0회**. |
| **왜 이런 결과가 나왔는가** | 부하가 상대적으로 작고(3노드, 제한된 파드 수), 리소스 여유가 있어 OOM·재시작이 발생하지 않음. |
| **우리 SLO 제안·결정 방법** | (1) **기본 0건/0회 유지**. (2) 특정 컴포넌트만 “N회까지 재시작 허용”이 필요하면 `RESTART_COUNT_THRESHOLD_OVERRIDES` 등으로 예외를 두고 **이유를 문서화**. (3) **방법론**: 인수 테스트마다 OOM·재시작 로그를 확인하고, 0이 아니면 원인 조사 후 수정·재테스트. |

---

### 2.8 핵심 요약 표 (CL2 임계치 vs 테스트 결과 vs 제안 SLO)

아래 표는 **인수 기준을 한눈에** 보기 위한 핵심 요약이다.

| SLI(무엇을 측정) | SLO 기준(무엇을 만족해야 함) | CL2 기본 임계치 | 테스트 결과(본 클러스터) | 제안 SLO(우리 기준) | 방향성 |
|---|---|---:|---:|---:|---|
| Pod 시작 지연 `PodStartupLatency` (P99, `pod_startup`) | 파드가 만들어진 뒤 Running까지 | 5s | **10.69s** (Prom 6443 run) / 16.11s (no-prom run) | **15s** | 이미지 프리로드/리소스 개선 후 5s로 단계적 강화 |
| API 단일 리소스 지연 `APIResponsivenessPrometheus` (P99, scope=resource) | GET/PUT/POST 등 단일 리소스 API | 1s | **0.361s** (예: replicasets/status PUT P99 360.7ms) | 1s | 기본 유지(업스트림) |
| API LIST 지연 `APIResponsivenessPrometheus` (P99, LIST) | namespace LIST / cluster LIST | 5s / 30s | **0.050s** (예: nodes LIST P99 49.5ms) | 5s / 30s | 기본 유지(업스트림) |
| DNS 조회 지연 `DnsLookupLatency` (P99) | DNS 응답 지연 | (별도 기본 SLO 없음) | **0.475s** | (제안) 1s | 원인(코어DNS 부하 등) 관찰하며 강화 |
| 스케줄러 처리량 `SchedulingThroughputPrometheus` (max) | 초당 스케줄 파드 수(높을수록 좋음) | 100 pods/s | **5.6 pods/s** | **10 pods/s** (3노드 기준) | 노드 수에 비례한 목표로 점진 상향 |
| 네트워크 프로그래밍 지연 `NetworkProgrammingLatency` (P99) | 서비스/엔드포인트 변경 반영 | 30s | **측정 실패 (0 samples)** | 30s (보류) | kube-proxy 스크랩/레코딩 룰/워크로드 이벤트 확보 후 재측정 |
| 시스템 안정성 (OOM/재시작) | OOM/재시작 없음 | 0건/0회 | **0건/0회** | 0건/0회 | 기본 유지 |

---

## 3. 기준 설정의 근거

- **Pod 시작 지연 5s**: Kubernetes 공식 [Pod Startup Latency SLO](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/pod_startup_latency.md) (P99 ≤ 5s).
- **API 지연 1s / 5s / 30s**: Kubernetes 공식 [API Call Latency SLO](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/api_call_latency.md).
- **네트워크 프로그래밍 30s**: [Network Programming Latency SLO](https://github.com/kubernetes/community/blob/master/sig-scalability/slos/network_programming_latency.md).
- **기타**: CL2 기본값 사용. 완화 시 **이유를 기록**한다.

---

## 4. 테스트 실행 방법

```bash
./scripts/run-load-acceptance.sh [report-dir]
# 또는 --provider=kind --nodes=3 등 지정하여 직접 실행
```

---

## 5. 지표 추출 방법 (결과 JSON에서 값 채우기)

- **Pod 시작 지연**: `results/load-acceptance/PodStartupLatency_*_load_*.json` → `labels.Metric == "pod_startup"` 항목의 `data.Perc99` (ms).
- **API 응답**: `APIResponsivenessPrometheus_simple_load_*.json` (Prometheus 필요).
- **네트워크 프로그래밍**: `NetworkProgrammingLatency_*.json` (Prometheus 필요).
- **OOM**: `ClusterOOMsTracker_*.json`. **시스템 파드**: `SystemPodMetrics_*.json`.

---

## 6. 인수 테스트 수행 결과 (직접 실행)

### 6.1 실행 개요 (no-Prometheus run)

| 항목 | 내용 |
|------|------|
| **실행 일시** | 2026-03-14 19:04 ~ 19:06 (KST) |
| **환경** | kind 3노드 (1 control-plane, 2 worker), Kubernetes v1.35.0 |
| **오버라이드** | `testing/load/ol-test.yaml` (Pod 5s, 네트워크 30s, Prometheus 미사용) |
| **실제 실행** | `--enable-prometheus-server=false` (Prometheus 미기동으로 실행) |
| **리포트 디렉터리** | `results/load-acceptance/` |

### 6.2 측정된 지표 (no-Prometheus run)

#### Pod 시작 지연 (CreatePhasePodStartupLatency)

| 구간 | P50 | P90 | P99 | 비고 |
|------|-----|-----|-----|------|
| create_to_schedule | 0 ms | 1 s | 4 s | |
| schedule_to_run | 4 s | 12 s | 13 s | |
| run_to_watch | 1.48 s | 3.32 s | 8.43 s | |
| schedule_to_watch | 6.41 s | 13.59 s | 14.71 s | |
| **pod_startup (전 구간)** | **7.47 s** | **13.67 s** | **16.11 s** | K8s SLO 5s 초과 |

- **사용자 관점**: “파드가 Running 되기까지” 전체 구간(pod_startup) P99 **약 16.1초**.
- **판정**: 공식 SLO(5s) 대비 **미달**. 로컬/kind 환경에서 이미지 풀·리소스 제약으로 지연이 커질 수 있음.

#### 시스템 안정성

- **ClusterOOMsTracker**: OOM 발생 **0건** (`failures: []`).
- **SystemPodMetrics**: 시스템 파드(etcd, apiserver, controller-manager, scheduler, coredns, kindnet 등) **재시작 0회**.

### 6.3 미측정·실패 항목 및 사유 (no-Prometheus run)

| 항목 | 상태 | 사유 |
|------|------|------|
| API 응답 지연 (APIResponsivenessPrometheus / Simple) | 미측정 | Prometheus 비활성으로 스킵. |
| 네트워크 프로그래밍 지연 (NetworkProgrammingLatency) | 미측정 | Prometheus 비활성으로 스킵. |
| 클러스터 내 네트워크 지연 (InClusterNetworkLatency) | 미측정 | Prometheus 비활성으로 스킵. |
| SLOMeasurement, ResourceSize, Kube-proxy iptables | 미측정 | Prometheus 비활성으로 스킵. |
| **TestMetrics (SchedulingMetrics)** | **실패** | Pod proxy 호출 시 `https:kube-scheduler-...:10259` 형식으로 인한 API 오류 (kind 환경에서 알려진 이슈). |

- Prometheus를 켜면 API 응답·네트워크 프로그래밍 등 추가 지표 수집 가능. 동일 run에서 Prometheus 기동이 완료되지 않아 본회 실행은 Prometheus 없이 진행함.

### 6.4 테스트 실행 결과 요약 (no-Prometheus run)

- **전체 테스트**: **Fail** (JUnit 기준 실패 3건 — 모두 SchedulingMetrics 연동 실패).
- **수집 성공**: Pod 시작 지연(CreatePhase), ClusterOOMs, SystemPodMetrics, ResourceUsageSummary, MetricsForE2E 등.
- **수집 실패/미수행**: API 응답, 네트워크 프로그래밍, 스케줄러 메트릭(TestMetrics 내 SchedulingMetrics).

---

### 6.5 실행 개요 (Prometheus 6443 run)

| 항목 | 내용 |
|------|------|
| **실행 일시** | 2026-03-14 19:37 ~ 19:43 (KST) |
| **환경** | kind 3노드 (Kubernetes v1.35.0) |
| **Prometheus 설정** | `--prometheus-apiserver-scrape-port=6443`, `--prometheus-memory-request=400Mi` |
| **리포트 디렉터리** | `results/load-prom-6443/` |
| **결과** | Fail (SchedulingMetrics + NetworkProgrammingLatency) |

### 6.6 측정된 핵심 SLI (Prometheus 6443 run)

| SLI | 결과 (P99 등) | CL2 임계치 | 판정 |
|-----|---------------|------------|------|
| **Pod 시작 지연 (pod_startup P99)** | **10.69s** | 5s | 미달 |
| **API 단일 리소스 (예: replicasets/status PUT P99)** | **360.7ms** | 1s | 충족 |
| **API LIST (예: nodes LIST P99)** | **49.5ms** | 30s (cluster) | 충족 |
| **DNS 조회 (DnsLookupLatency P99)** | **474.9ms** | (미설정) | 관찰 |
| **스케줄러 처리량 (max)** | **5.6 pods/s** | 100 pods/s | 미달(소규모 환경) |
| **클러스터 내 네트워크 (InClusterNetworkLatency P99)** | **0ms** | 0s(미검사) | 결과 신뢰 낮음(측정치 0) |
| **OOM/시스템 파드 재시작** | 0건/0회 | 0건/0회 | 충족 |

### 6.7 실패·보류 항목 (Prometheus 6443 run)

| 항목 | 상태 | 원인/해석 |
|------|------|----------|
| **SchedulingMetrics (TestMetrics)** | 실패 | kind 환경에서 scheduler metrics를 Pod proxy로 접근할 때 `unknown (get pods https:kube-scheduler-...:10259)` 오류가 반복됨. |
| **NetworkProgrammingLatency** | 실패 | Prometheus 쿼리가 **0 samples**로 실패. 보통 (1) kube-proxy 메트릭/레코딩 룰 미생성 또는 (2) 테스트 구간에 network programming 이벤트 부족(서비스/엔드포인트 변경 부족)일 때 발생. |


---

## 7. 최종 인수 기준 제안 (이 클러스터 환경)

실제 측정값과 환경을 반영한 **제안 기준**는 아래와 같다.

| 지표 | 제안 임계치 | 근거 |
|------|-------------|------|
| Pod 시작 지연 (P99) | **15s** (또는 1회성 기준 20s) | 본 run P99 16.1s. kind/로컬에서 이미지·리소스 이슈로 5s 달성 어려움. 15s는 “대부분 구간이 이 안에 끝난다”는 수준으로 완화. |
| API 단일 리소스 (P99) | 1s | K8s SLO 유지 (Prometheus 측정 시 적용). |
| API LIST (P99) | 5s / 30s | K8s SLO 유지 (Prometheus 측정 시 적용). |
| 네트워크 프로그래밍 (P99) | 30s | K8s SLO 유지 (Prometheus 측정 시 적용). |
| OOM | 0건 | 본 run 기준 충족. |
| 시스템 파드 재시작 | 0회 | 본 run 기준 충족. |

- **SchedulingMetrics**: 현재 kind 환경에서 동일 오류가 나므로, 인수 조건에서 “제외”하거나, 수정/워크어라운드 적용 후 재측정 시 포함하는 것을 권장.

---

## 8. 결론 (비전문가 관리자용)

- **이번 인수 테스트**에서 직접 수행한 결과는 다음과 같다.
  - **측정된 것**: 파드 시작 지연(전 구간 P99 약 16초), OOM 없음, 시스템 파드 재시작 없음.
  - **측정되지 않은 것**: API 응답 속도, 네트워크 프로그래밍 지연, 스케줄러 메트릭 (Prometheus 미사용 및 kind 측 스케줄러 메트릭 접근 오류).
- **Pod 시작**은 공식 SLO(5초)보다 느리나, **로컬/kind 환경**을 고려해 **“P99 15초 이하”**를 이 클러스터의 인수 기준으로 제안한다. 필요 시 “첫 실행 20초 이하” 등 1회성 완화도 가능.
- **API·네트워크·스케줄러** 지표는 Prometheus를 활성화하고, kind에서 스케줄러 메트릭 접근 이슈를 피하거나 수정한 뒤 **재실행하여 보완 측정**하는 것을 권장한다.

**정리**: 본회 실행으로 **Pod 시작 지연, OOM, 시스템 파드 안정성**에 대한 인수 테스트는 수행되었고, 그 결과를 바탕으로 **Pod 시작에 대한 임계치(15s)** 를 제안하였다. 나머지 지표는 Prometheus 및 환경 이슈 해결 후 추가 실행으로 인수 기준을 보완할 수 있다.

---

*실제 결과 파일: `results/load-acceptance/` (junit.xml, PodStartupLatency_*.json, ClusterOOMsTracker_*.json, SystemPodMetrics_*.json 등).*
