# Prometheus (ClusterLoader2)

ClusterLoader2에서 사용하는 Prometheus 스택 안내.

## UI 접속

### Prometheus
```bash
kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090 --address=0.0.0.0
```
→ http://localhost:9090

### Grafana
```bash
kubectl --namespace monitoring port-forward svc/grafana 3000 --address=0.0.0.0
```
→ http://localhost:3000 (로그인: admin / admin)

---

## 플래그·환경변수 요약

커맨드라인 `--플래그` 또는 **환경변수**로 지정 가능.

### 서버 설치·삭제

| 플래그 | 환경변수 | 기본값 | 설명 |
|--------|----------|--------|------|
| `--enable-prometheus-server` | `ENABLE_PROMETHEUS_SERVER` | false | 클러스터에 Prometheus 스택 설치 여부 |
| `--tear-down-prometheus-server` | `TEAR_DOWN_PROMETHEUS_SERVER` | true | 테스트 후 Prometheus 스택 삭제 여부 |
| `--enable-pushgateway` | `PROMETHEUS_ENABLE_PUSHGATEWAY` | false | Pushgateway 설치 (배치 잡 등 단발 메트릭용) |

### 스크래핑 대상

| 플래그 | 환경변수 | 기본값 | 설명 |
|--------|----------|--------|------|
| `--prometheus-scrape-etcd` | `PROMETHEUS_SCRAPE_ETCD` | false | etcd 메트릭 (2379, 2382) |
| `--prometheus-scrape-node-exporter` | `PROMETHEUS_SCRAPE_NODE_EXPORTER` | false | node-exporter |
| `--prometheus-scrape-windows-node-exporter` | `PROMETHEUS_SCRAPE_WINDOWS_NODE_EXPORTER` | false | Windows node-exporter |
| `--prometheus-scrape-kubelets` | `PROMETHEUS_SCRAPE_KUBELETS` | false | kubelet (노드+마스터), 대규모 클러스터에서는 실험적 |
| `--prometheus-scrape-master-kubelets` | `PROMETHEUS_SCRAPE_MASTER_KUBELETS` | false | 마스터 노드 kubelet만 |
| `--prometheus-scrape-kube-proxy` | `PROMETHEUS_SCRAPE_KUBE_PROXY` | **true** | kube-proxy (NetworkProgrammingLatency 등에 필요) |
| `--prometheus-kube-proxy-selector-key` | `PROMETHEUS_KUBE_PROXY_SELECTOR_KEY` | "component" | kube-proxy Pod 선택 라벨 키 |
| `--prometheus-scrape-kube-state-metrics` | `PROMETHEUS_SCRAPE_KUBE_STATE_METRICS` | false | kube-state-metrics |
| `--prometheus-scrape-metrics-server` | `PROMETHEUS_SCRAPE_METRICS_SERVER_METRICS` | false | metrics-server |
| `--prometheus-scrape-node-local-dns` | `PROMETHEUS_SCRAPE_NODE_LOCAL_DNS` | false | node-local-dns |
| `--prometheus-scrape-anet` | `PROMETHEUS_SCRAPE_ANET` | false | anet Pod |
| `--prometheus-scrape-kube-network-policies` | `PROMETHEUS_SCRAPE_KUBE_NETWORK_POLICIES` | false | kube-network-policies |
| `--prometheus-scrape-masters-with-public-ips` | `PROMETHEUS_SCRAPE_MASTERS_WITH_PUBLIC_IPS` | false | 마스터를 퍼블릭 IP로 스크래핑 |

### apiserver

| 플래그 | 환경변수 | 기본값 | 설명 |
|--------|----------|--------|------|
| `--prometheus-apiserver-scrape-port` | `PROMETHEUS_APISERVER_SCRAPE_PORT` | 443 | kube-apiserver 메트릭 포트. **kind**는 6443 권장 |

### 스토리지·리소스·기타

| 플래그 | 환경변수 | 기본값 | 설명 |
|--------|----------|--------|------|
| `--experimental-snapshot-project` | `PROJECT` | "" | GCP 스냅샷용 프로젝트 |
| `--prometheus-additional-monitors-path` | `PROMETHEUS_ADDITIONAL_MONITORS_PATH` | "" | 추가 ServiceMonitor 등 경로 |
| `--prometheus-storage-class-provisioner` | `PROMETHEUS_STORAGE_CLASS_PROVISIONER` | "kubernetes.io/gce-pd" | PV 프로비저너 |
| `--prometheus-storage-class-volume-type` | `PROMETHEUS_STORAGE_CLASS_VOLUME_TYPE` | "pd-ssd" | 볼륨 타입 |
| `--prometheus-pvc-storage-class` | `PROMETHEUS_PVC_STORAGE_CLASS` | "ssd" | Prometheus PVC용 StorageClass 이름 |
| `--prometheus-ready-timeout` | `PROMETHEUS_READY_TIMEOUT` | 15m | 스택 준비 대기 타임아웃 |
| `--prometheus-memory-request` | `PROMETHEUS_MEMORY_REQUEST` | "10Gi" | Prometheus Pod 메모리 request (소규모는 "400Mi" 등) |

---

## 예시: metrics-server 지연 측정

- `--provider=gce`
- `--enable-prometheus-server=true`
- `--prometheus-scrape-metrics-server=true`

---

## kind에서 쓰기

- apiserver 포트: `--prometheus-apiserver-scrape-port=6443`
- 메모리: `--prometheus-memory-request=400Mi`
- PVC 비활성화(emptyDir 사용): 오버레이에 `CL2_PROMETHEUS_PVC_ENABLED: false`
- apiserver만 스크래핑(마스터 타깃 down 방지): 오버레이에 `PROMETHEUS_SCRAPE_APISERVER_ONLY: true`

자세한 구현은 `pkg/prometheus/` 참고.
