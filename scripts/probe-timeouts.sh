#!/usr/bin/env bash
# Политика проб: явный timeoutSeconds у каждой пробы. Дефолт Kubernetes — одна
# секунда, и для exec-пробы этого мало: exec идёт через kubelet и containerd и
# измеряет ещё и загрузку ноды, поэтому на перегруженном узле не проходит ни
# одна попытка, а failureThreshold не спасает — под убивается по кругу (инцидент
# 0010). Дефект невидим: в манифесте поля нет, дефолт подставляет API, линтеры
# молчат, а проявляется он только под нагрузкой.
#
#   ./scripts/probe-timeouts.sh --check
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

problems="$(
  git ls-files 'clusters/casa/*.yaml' |
    xargs -r awk '
    function lead(s) {
      t = s
      sub(/^[ \t]+/, "", t)
      return length(s) - length(t)
    }
    function flush() {
      if (probe == "") return
      if (timeout == "") {
        printf "%s:%d: %s без timeoutSeconds\n", file, line, probe
      } else if (timeout + 0 < 2) {
        printf "%s:%d: %s timeoutSeconds=%s — секунда и около не принимаются\n", file, line, probe, timeout
      } else if (check == "exec" && timeout + 0 < 5) {
        printf "%s:%d: exec-проба %s с timeoutSeconds=%s — exec измеряет ещё и ноду\n", file, line, probe, timeout
      }
      probe = ""
      check = ""
      timeout = ""
    }
    FNR == 1 {
      flush()
      file = FILENAME
    }
    {
      if (probe != "" && $0 ~ /^[ \t]*$/) next
      is_probe = ($0 ~ /^[ \t]*(startupProbe|readinessProbe|livenessProbe):[ \t]*$/)
      if (probe != "" && (is_probe || lead($0) <= indent)) flush()
      if (is_probe) {
        probe = $1
        sub(/:$/, "", probe)
        indent = lead($0)
        line = FNR
        next
      }
      if (probe != "" && lead($0) > indent) {
        if ($1 ~ /^(exec|httpGet|tcpSocket|grpc):$/) {
          check = $1
          sub(/:$/, "", check)
        }
        if ($1 == "timeoutSeconds:") timeout = $2
        next
      }
    }
    END { flush() }
    '
)"

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" >&2
  printf 'проб с недопустимым таймаутом: %d\n' "$(printf '%s\n' "$problems" | wc -l | tr -d ' ')" >&2
  exit 1
fi

printf 'все пробы объявляют timeoutSeconds\n'
