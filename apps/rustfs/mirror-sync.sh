#!/usr/bin/env bash
#
# Зеркалит артефакты в RustFS (бакет mirror) и открывает бакет на анонимное
# чтение, чтобы CI тянул их без интернета и без креденшелов.
#
# Запускается in-cluster как CronJob mirror-sync (образ amazon/aws-cli): у пода
# есть egress к upstream'ам, aws-cli, curl и sha256sum; git/tar для сборки схем
# доустанавливаются на ходу. Артефакты, уже лежащие в бакете, пропускаются —
# зеркало append-only (чтобы заменить версию, удалить объект и перезапустить).
#
# Манифест (apps/rustfs/artifacts.tsv, смонтирован в /scripts/artifacts.tsv) —
# строки "<path> <sha256> <url>".
#
# Окружение:
#   S3_ENDPOINT         S3 API RustFS (например http://rustfs.rustfs.svc.cluster.local:9000)
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

ensure_bucket() {
  if ! s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    s3api create-bucket --bucket "$BUCKET"
  fi
  # Бакет читается анонимно: CI тянет артефакты без креденшелов.
  s3api put-bucket-policy --bucket "$BUCKET" --policy "$(cat <<JSON
{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::$BUCKET/*"]}]}
JSON
)"
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
  curl -fsSL -o "$tmp" "$url"
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

ensure_bucket

while read -r path sha url _; do
  [ -z "${path:-}" ] && continue
  case "$path" in \#*) continue ;; esac
  [ -z "${url:-}" ] && continue
  sync_url "$path" "$sha" "$url"
done < "$MANIFEST"

if [ -n "${KUBERNETES_VERSION:-}" ]; then
  sync_schemas "$KUBERNETES_VERSION"
fi

echo "mirror sync done"
