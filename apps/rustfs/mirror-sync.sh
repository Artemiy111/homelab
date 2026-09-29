#!/usr/bin/env bash
#
# Зеркалит артефакты в RustFS (бакет mirror), чтобы CI тянул их без интернета и
# без креденшелов. Бакет и public-read policy принадлежат terraform/rustfs, здесь
# остаётся только заливка объектов.
#
# Запускается in-cluster как CronJob mirror-sync (образ amazon/aws-cli): у пода
# есть egress к upstream'ам, aws-cli, curl и sha256sum; git/tar для сборки схем
# доустанавливаются на ходу. Артефакты, уже лежащие в бакете, пропускаются —
# зеркало append-only (чтобы заменить версию, удалить объект и перезапустить).
# Недоступный апстрим не останавливает прогон: цикл доходит до конца манифеста,
# неудачные артефакты перечисляются в конце, Job завершается ненулевым кодом.
#
# Манифест (apps/rustfs/artifacts.tsv, смонтирован в /scripts/artifacts.tsv) —
# строки "<path> <sha256> <url>".
#
# Окружение:
#   S3_ENDPOINT         S3 API RustFS (например http://rustfs.rustfs.svc.cluster.local)
#   MIRROR_BUCKET       имя бакета (по умолчанию mirror)
#   KUBERNETES_VERSION  если задано — собрать и опубликовать схемы kubeconform
#   SCHEMA_REPO         upstream репозиторий схем (по умолчанию yannh/kubernetes-json-schema)
set -euo pipefail

: "${S3_ENDPOINT:?задайте S3_ENDPOINT}"
BUCKET="${MIRROR_BUCKET:-mirror}"
MANIFEST="${MIRROR_MANIFEST:-/scripts/artifacts.tsv}"
SCHEMA_REPO="${SCHEMA_REPO:-https://github.com/yannh/kubernetes-json-schema.git}"

s3api() { aws --endpoint-url "$S3_ENDPOINT" s3api "$@"; }
s3cp() { aws --endpoint-url "$S3_ENDPOINT" s3 cp "$@"; }

ensure_build_tools() {
  command -v git >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && return 0
  dnf install -y git tar gzip >/dev/null 2>&1
}

object_exists() {
  s3api head-object --bucket "$BUCKET" --key "$1" >/dev/null 2>&1
}

sync_url() {
  local path="$1" sha="$2" url="$3" tmp got
  if object_exists "$path"; then
    echo "skip $path"
    return 0
  fi
  echo "fetch $path"
  tmp="$(mktemp)"
  if ! curl -fsSL -o "$tmp" "$url"; then
    echo "fetch failed for $path: $url" >&2
    rm -f "$tmp"
    return 1
  fi
  got="$(sha256sum "$tmp" | awk '{print $1}')"
  if [ "$got" != "$sha" ]; then
    echo "sha256 mismatch for $path: got $got want $sha" >&2
    rm -f "$tmp"
    return 1
  fi
  s3cp "$tmp" "s3://$BUCKET/$path"
  rm -f "$tmp"
}

# Схемы kubeconform лежат подкаталогом в монорепе yannh/kubernetes-json-schema,
# готового URL-архива нет — собираем sparse-checkout'ом. mtime/владелец
# фиксируем, чтобы архив не зависел от окружения.
sync_schemas() {
  local ver="$1" path tmp
  [ -z "$ver" ] && return 0
  path="kubeconform-schemas/$ver/kubernetes-json-schema_${ver}_standalone.tar.gz"
  if object_exists "$path"; then
    echo "skip $path"
    return 0
  fi
  echo "build $path"
  ensure_build_tools
  tmp="$(mktemp -d)"
  git clone --depth 1 --filter=blob:none --sparse "$SCHEMA_REPO" "$tmp/schemas"
  git -C "$tmp/schemas" sparse-checkout set "v${ver}-standalone"
  tar -C "$tmp/schemas" \
    --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -czf "$tmp/schemas.tar.gz" "v${ver}-standalone"
  s3cp "$tmp/schemas.tar.gz" "s3://$BUCKET/$path"
  rm -rf "$tmp"
}

failed=()

while read -r path sha url _; do
  [ -z "${path:-}" ] && continue
  case "$path" in \#*) continue ;; esac
  [ -z "${url:-}" ] && continue
  if ! sync_url "$path" "$sha" "$url"; then
    failed+=("$path")
  fi
done < "$MANIFEST"

if [ -n "${KUBERNETES_VERSION:-}" ]; then
  if ! sync_schemas "$KUBERNETES_VERSION"; then
    failed+=("kubeconform-schemas/$KUBERNETES_VERSION")
  fi
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo "mirror sync finished with ${#failed[@]} failure(s):" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi

echo "mirror sync done"
