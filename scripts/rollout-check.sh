#!/usr/bin/env bash
# Zero-downtime proof: hit the app continuously during a rollout and count
# every non-200 response. Stop with Ctrl-C; the summary prints on exit.
#
#   scripts/rollout-check.sh [url] [interval-seconds]
#
# Each line logs: timestamp, HTTP status, version and pod that answered.
set -euo pipefail

URL="${1:-http://hello.127.0.0.1.nip.io/}"
INTERVAL="${2:-0.2}"
LOG="rollout-check-$(date +%Y%m%d-%H%M%S).log"

total=0
failed=0

summary() {
  echo
  echo "Requests: ${total}  Non-200: ${failed}  Log: ${LOG}"
  if [[ "${failed}" -eq 0 ]]; then echo "RESULT: zero downtime"; else echo "RESULT: ${failed} failed requests"; fi
}
trap summary EXIT
trap 'exit 0' INT TERM

echo "Polling ${URL} every ${INTERVAL}s, logging to ${LOG} (Ctrl-C to stop)"
while true; do
  body_file="$(mktemp)"
  code="$(curl -s -o "${body_file}" -w '%{http_code}' --max-time 2 "${URL}" || true)"
  # The page renders "Version: <sha>" and "Pod: <name>"; pull them out for the log.
  version="$(grep -oE 'Version:[^<]*<[^>]*>[^<]+' "${body_file}" | sed -E 's/.*>//' | head -1 || true)"
  pod="$(grep -oE 'Pod:[^<]*<[^>]*>[^<]+' "${body_file}" | sed -E 's/.*>//' | head -1 || true)"
  rm -f "${body_file}"

  total=$((total + 1))
  [[ "${code}" == "200" ]] || failed=$((failed + 1))
  printf '%s %s version=%s pod=%s\n' "$(date +%H:%M:%S)" "${code}" "${version:-?}" "${pod:-?}" | tee -a "${LOG}"
  sleep "${INTERVAL}"
done
