#!/usr/bin/env bash
# Политика prune: у приложений Argo prune включён, а у ресурсов, потеря которых
# необратима, снят аннотацией. Проверка держит это соответствие, потому что
# расходится оно молча: новый юнит копирует соседний манифест, решение живёт в
# `docs/adr/0013`, а Argo удаляет то, чего нет в git, без предупреждения.
#
#   ./scripts/argocd-prune.sh --check
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

apps=0
resources=0
failures=0

# 1. Application юнита с автоматической синхронизацией обязан нести
# `prune: true`. Платформенные компоненты сюда не входят: они ставят операторов,
# и там prune выключен осознанно — кластерные CRD из git не удаляются
# (app-level `Prune=false`, см. `clusters/casa/platform/*/app.yaml`).
while IFS= read -r file; do
  grep -q '^ *automated:' "$file" || continue
  apps=$((apps + 1))
  if ! grep -q '^ *prune: true' "$file"; then
    printf '%s: automated без prune: true\n' "$file" >&2
    failures=$((failures + 1))
  fi
done < <(git ls-files 'clusters/casa/apps/*/app.yaml')

# 2. То, что Argo не должен удалять сам, помечено `Prune=false`. Проверяем по
# документам, а не по файлам: в одном файле могут лежать несколько ресурсов.
while IFS= read -r file; do
  awk -v file="$file" '
    function check() {
      if (kind == "PersistentVolumeClaim" || kind == "Namespace") {
        seen++
        if (!optout) {
          printf "%s: %s без argocd.argoproj.io/sync-options: Prune=false\n", file, kind > "/dev/stderr"
          bad = 1
        }
      }
      kind = ""; optout = 0
    }
    /^---[[:space:]]*$/ { check(); next }
    /^kind:[[:space:]]/ { if (kind == "") kind = $2 }
    /argocd\.argoproj\.io\/sync-options:/ { if (index($0, "Prune=false")) optout = 1 }
    END { check(); printf "%d\n", seen; if (bad) exit 1 }
  ' "$file" >>"${TMPDIR:-/tmp}/argocd-prune-seen.$$" || failures=$((failures + 1))
done < <(git ls-files 'clusters/casa/*.yaml')

resources=$(awk '{ sum += $1 } END { print sum + 0 }' "${TMPDIR:-/tmp}/argocd-prune-seen.$$" 2>/dev/null || echo 0)
rm -f "${TMPDIR:-/tmp}/argocd-prune-seen.$$"

# 3. Политика обязана доезжать до кластера. С `ignoreDifferences` на
# `/spec/syncPolicy/automated` у root `prune` из `app.yaml` не применяется —
# приложения при этом выглядят исправными, и Synced ничего не значит.
if grep -q '/spec/syncPolicy/automated' bootstrap/root.yaml; then
  printf 'bootstrap/root.yaml: ignoreDifferences на /spec/syncPolicy/automated глушит prune из app.yaml\n' >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  printf 'нарушений политики prune: %d\n' "$failures" >&2
  exit 1
fi

printf 'приложений с prune: true — %d, защищённых ресурсов (PVC и namespace) — %d\n' "$apps" "$resources"
