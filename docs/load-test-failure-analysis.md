# Load 테스트 실패 원인 분석 (SchedulingMetrics / NetworkProgrammingLatency)

## 1. SchedulingMetrics – `unknown (get pods https:kube-scheduler-kind-control-plane:10259)`

### 결론: **Pod proxy 이름 형식 불일치**

- 코드에서는 **Service** proxy와 동일하게 `https:podname:port` 형식을 사용함.
  - `pkg/measurement/common/scheduler_latency.go` 305라인: `Name(fmt.Sprintf("https:kube-scheduler-%v:%v", masterName, kubeSchedulerPort))`
  - `pkg/measurement/common/metrics/metrics_grabber.go` 268라인: HTTPS일 때 `name = fmt.Sprintf("https:%s:%d", podName, port)` (동일 패턴)
- Kubernetes 문서/동작을 보면:
  - **Service** proxy: `scheme:service-name:port` (예: `http:service-name:8080`) 형식이 명시적으로 지원됨.
  - **Pod** proxy: 공식 문서는 대부분 `pod-name:port` 만 언급하고, `scheme:pod-name:port` 는 서비스용 예시에서만 등장함.
- 따라서 **Pod** proxy에서 API 서버가 `scheme:` 접두사를 **지원하지 않거나** 파싱 방식이 다를 가능성이 큼.  
  이 경우 `https:kube-scheduler-kind-control-plane:10259` 전체가 리소스 이름으로 해석되거나, `podname`이 `https:kube-scheduler-kind-control-plane`으로 잘못 파싱되어 **해당 이름의 Pod를 찾지 못해** `get pods https:kube-scheduler-kind-control-plane:10259` 요청이 실패하고, 클라이언트에서 이를 `unknown` 형태로 노출하는 것으로 보는 것이 타당함.

### 요약

| 항목 | 내용 |
|------|------|
| **원인** | Pod proxy 리소스 이름에 `https:` 를 넣은 형식이, **Pod** 에서는 지원되지 않거나 다르게 파싱됨. (Service에서는 지원되는 형식) |
| **증상** | `get pods https:kube-scheduler-kind-control-plane:10259` 요청 실패 → `unknown` 등으로 표시 |
| **근거** | 동일 코드베이스의 metrics_grabber는 같은 형식을 쓰지만, API 스펙/문서상 Pod는 `name:port` 만 명확히 문서화됨. |

---

## 2. NetworkProgrammingLatency – `got unexpected number of samples: 0`

### 결론: **Prometheus에 해당 메트릭/레코딩 룰 결과가 없음**

- 측정 로직은 **정확히 3개** 샘플(quantile 0.5, 0.9, 0.99)을 기대함.  
  `pkg/measurement/common/slos/network_programming.go` 103라인: `if len(samples) != 3`.
- 사용 쿼리:  
  `quantile_over_time(0.99, kubeproxy:kubeproxy_network_programming_duration:histogram_quantile{}[%v])`  
  → 이 메트릭은 **레코딩 룰** 결과임.
- 레코딩 룰 정의: `pkg/prometheus/manifests/prometheus-rules.yaml` 의 `kube-proxy.rules`:
  - 원본 메트릭: `kubeproxy_network_programming_duration_seconds_bucket`
  - `rate(...[5m])` 기반으로 0.5/0.9/0.99 quantile 레코딩 룰 생성.
- 0개 샘플이 나오는 경우는 다음 중 하나(또는 조합)임:

| 가능 원인 | 설명 |
|-----------|------|
| **스크랩/대상 부재** | kube-proxy가 스크랩되지 않아 `kubeproxy_network_programming_duration_seconds_bucket` 자체가 없음. (ServiceMonitor/라벨 불일치, Prometheus가 해당 타겟을 선택하지 않음 등) |
| **데이터 구간 부족** | 레코딩 룰이 `rate(...[5m])` 를 쓰므로 **최소 5분** 이상 kube-proxy 메트릭이 쌓여야 함. 테스트가 짧거나 Prometheus 기동 직후면 구간 내 데이터가 없을 수 있음. |
| **관측 이벤트 부재** | `network_programming_duration_seconds` 는 **엔드포인트/서비스 변경이 반영될 때**만 관측됨 (Kubernetes pkg/proxy/metrics). 테스트 동안 서비스/엔드포인트 변경이 없으면 히스토그램에 관측치가 없고, `rate()`/quantile 결과도 없어 0개 시리즈가 됨. |

### 요약

| 항목 | 내용 |
|------|------|
| **원인** | 쿼리 대상 메트릭 `kubeproxy:kubeproxy_network_programming_duration:histogram_quantile` 이 해당 시간 구간에 **존재하지 않음** (0개 시리즈). |
| **가능한 이유** | (1) kube-proxy 스크랩 미동작, (2) 5분 미만 등 데이터 구간 부족, (3) 테스트 중 네트워크 프로그래밍 이벤트(엔드포인트/서비스 변경) 없음. |

---

## 참고

- 스케줄러 메트릭은 **Pod** proxy로 접근하고, kube-proxy 메트릭은 **Prometheus 레코딩 룰 + 스크랩** 에 의존함.
- 위 두 가지는 각각 **API 사용 방식(Pod proxy 이름)** 과 **Prometheus/테스트 환경(스크랩·시간·워크로드)** 에 대한 이슈로 보는 것이 타당함.
