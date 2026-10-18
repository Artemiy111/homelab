#!/usr/bin/env bash
# Политика проб. Дефолт Kubernetes — таймаут в одну секунду, и для exec-пробы
# этого мало: exec идёт через kubelet и containerd и измеряет ещё и загрузку
# ноды, поэтому на перегруженном узле не проходит ни одна попытка, а
# failureThreshold не спасает — под убивается по кругу (инцидент 0010). Дефект
# невидим: в манифесте поля нет, дефолт подставляет API, линтеры молчат.
#
# Второе, что проверяется, — не отдельное поле, а окно, которое из полей
# складывается: тикер проб не сбрасывается между попытками и лишние тики
# дропаются, поэтому шаг между попытками равен max(periodSeconds,
# timeoutSeconds), а не сумме. Окно старта — initialDelaySeconds +
# failureThreshold × max(periodSeconds, timeoutSeconds); реакция readiness и
# liveness — failureThreshold × max(periodSeconds, timeoutSeconds).
#
#   ./scripts/probe-timeouts.sh --check
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

startup_limit=300
reaction_limit=120

problems="$(
  git ls-files 'apps/casa/*.yaml' 'platform/casa/*.yaml' 'clusters/casa/argocd/*.yaml' |
    xargs -r awk -v startup_limit="$startup_limit" -v reaction_limit="$reaction_limit" '
      function lead(s) {
        t = s
        sub(/^[ \t]+/, "", t)
        return length(s) - length(t)
      }
      function num(v, d) {
        return (v == "" ? d : v + 0)
      }
      function max2(a, b) {
        return (a > b ? a : b)
      }
      function flush(   window, reaction) {
        if (probe == "") return
        if (timeout == "") {
          printf "%s:%d: %s без timeoutSeconds\n", file, line, probe
        } else if (timeout + 0 < 2) {
          printf "%s:%d: %s timeoutSeconds=%s — секунда и около не принимаются\n", file, line, probe, timeout
        } else if (check == "exec" && timeout + 0 < 5) {
          printf "%s:%d: exec-проба %s с timeoutSeconds=%s — exec измеряет ещё и ноду\n", file, line, probe, timeout
        } else if (probe == "startupProbe") {
          if (threshold == "" || period == "") {
            printf "%s:%d: startupProbe без failureThreshold или periodSeconds — окно не посчитать\n", file, line
          } else {
            window = num(delay, 0) + num(threshold, 3) * max2(num(period, 10), timeout + 0)
            if (window > startup_limit) {
              printf "%s:%d: окно старта %dс больше %dс (delay %d + %d × max(%d, %d))\n", file, line, window, startup_limit, num(delay, 0), num(threshold, 3), num(period, 10), timeout + 0
            }
          }
        } else {
          if (threshold == "") {
            printf "%s:%d: %s без failureThreshold — реакцию не посчитать\n", file, line, probe
          } else {
            reaction = num(threshold, 3) * max2(num(period, 10), timeout + 0)
            if (reaction > reaction_limit) {
              printf "%s:%d: реакция %s %dс больше %dс (%d × max(%d, %d))\n", file, line, probe, reaction, reaction_limit, num(threshold, 3), num(period, 10), timeout + 0
            }
          }
        }
        probe = ""
        check = ""
        timeout = ""
        threshold = ""
        period = ""
        delay = ""
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
          if ($1 == "failureThreshold:") threshold = $2
          if ($1 == "periodSeconds:") period = $2
          if ($1 == "initialDelaySeconds:") delay = $2
          next
        }
      }
      END { flush() }
    '
)"

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" >&2
  printf 'проб с нарушением политики: %d\n' "$(printf '%s\n' "$problems" | wc -l | tr -d ' ')" >&2
  exit 1
fi

printf 'пробы в политике: окно старта не больше %sс, реакция не больше %sс\n' "$startup_limit" "$reaction_limit"
