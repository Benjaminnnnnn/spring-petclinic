#!/bin/bash

set -euo pipefail

TARGET_URL="${1:?Usage: zap-api-scan.sh <target-url> [zap-api-base] [zap-api-key] [report-dir]}"
ZAP_API_BASE="${2:-burpsuite:8090}"
ZAP_API_KEY="${3:-burp-api-key}"
REPORT_DIR="${4:-build/reports/dast}"

mkdir -p "${REPORT_DIR}"

if [[ "${ZAP_API_BASE}" != *"://"* ]]; then
	ZAP_API_BASE="$(printf 'http%s%s' '://' "${ZAP_API_BASE}")"
fi

echo "Preparing DAST scan for ${TARGET_URL}"

curl --fail --silent --show-error "${TARGET_URL}" > /dev/null

curl --fail --silent --show-error --get \
	--data-urlencode "apikey=${ZAP_API_KEY}" \
	--data-urlencode "url=${TARGET_URL}" \
	"${ZAP_API_BASE}/JSON/core/action/accessUrl/" > /dev/null

scan_id="$(curl --fail --silent --show-error --get \
	--data-urlencode "apikey=${ZAP_API_KEY}" \
	--data-urlencode "url=${TARGET_URL}" \
	--data-urlencode "maxChildren=10" \
	"${ZAP_API_BASE}/JSON/spider/action/scan/" | sed -n 's/.*"scan":"\([^"]*\)".*/\1/p')"

if [ -z "${scan_id}" ]; then
	echo "Unable to start OWASP ZAP spider scan" >&2
	exit 1
fi

for _ in $(seq 1 60); do
	status="$(curl --fail --silent --show-error --get \
		--data-urlencode "apikey=${ZAP_API_KEY}" \
		--data-urlencode "scanId=${scan_id}" \
		"${ZAP_API_BASE}/JSON/spider/view/status/" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
	if [ "${status}" = "100" ]; then
		break
	fi
	sleep 2
done

for _ in $(seq 1 30); do
	remaining="$(curl --fail --silent --show-error --get \
		--data-urlencode "apikey=${ZAP_API_KEY}" \
		"${ZAP_API_BASE}/JSON/pscan/view/recordsToScan/" | sed -n 's/.*"recordsToScan":"\([^"]*\)".*/\1/p')"
	if [ "${remaining}" = "0" ]; then
		break
	fi
	sleep 2
done

curl --fail --silent --show-error --get \
	--data-urlencode "apikey=${ZAP_API_KEY}" \
	"${ZAP_API_BASE}/OTHER/core/other/htmlreport/" > "${REPORT_DIR}/zap-report.html"

curl --fail --silent --show-error --get \
	--data-urlencode "apikey=${ZAP_API_KEY}" \
	--data-urlencode "baseurl=${TARGET_URL}" \
	"${ZAP_API_BASE}/JSON/core/view/alerts/" > "${REPORT_DIR}/zap-alerts.json"

echo "DAST report written to ${REPORT_DIR}/zap-report.html"
