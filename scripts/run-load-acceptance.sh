#!/usr/bin/env bash
# Load 테스트 실행 (인수 테스트용). 결과는 results/load/ 에 저장.
# 사용: ./scripts/run-load-acceptance.sh [report-dir]
#       report-dir 기본값: results/load
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
REPORT_DIR="${1:-results/load}"
mkdir -p "$REPORT_DIR"

echo "Running load test (config + ol-test.yaml override)..."
echo "Report dir: $REPORT_DIR"
go run ./cmd/clusterloader.go \
  --provider=kind \
  --nodes=3 \
  --enable-prometheus-server=true \
  --tear-down-prometheus-server=false \
  --testconfig=testing/load/config.yaml \
  --testoverrides=testing/load/ol-test.yaml \
  --report-dir="$REPORT_DIR"

echo "Done. Check $REPORT_DIR for JSON summaries and junit.xml."
echo "Fill docs/load-test-acceptance-report.md with measured values and final SLI/SLO."
