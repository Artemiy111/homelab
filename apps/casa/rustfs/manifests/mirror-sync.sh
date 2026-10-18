#!/usr/bin/env bash
#
# Зеркалит артефакты в RustFS (бакет mirror), чтобы CI тянул их без интернета и
# без креденшелов. Бакет и public-read policy принадлежат infra/terraform/rustfs, здесь
# остаётся только заливка объектов.
#
# Запускается in-cluster как CronJob mirror-sync (образ amazon/aws-cli): у пода
# есть egress к upstream'ам, aws-cli, curl и sha256sum; git/tar для сборки схем
# доустанавливаются на ходу. Артефакты, уже лежащие в бакете, пропускаются —
# зеркало append-only (чтобы заменить версию, удалить объект и перезапустить).
# Недоступный апстрим не останавливает прогон: цикл доходит до конца манифеста,
# неудачные артефакты перечисляются в конце, Job завершается ненулевым кодом.
#
# Манифест (clusters/casa/apps/rustfs/manifests/artifacts.tsv, смонтирован в /scripts/artifacts.tsv) —
# строки "<path> <sha256> <url>".
#
# Окружение:
#   S3_ENDPOINT         S3 API RustFS (например http://rustfs.rustfs.svc.cluster.local)
#   MIRROR_BUCKET       имя бакета (по умолчанию mirror)
#   KUBERNETES_VERSION  если задано — собрать и опубликовать схемы kubeconform
#   SCHEMA_REPO         upstream репозиторий схем (по умолчанию yannh/kubernetes-json-schema)
#   CRD_SCHEMAS_REV     ревизия каталога CR-схем datreeio/CRDs-catalog; если
#                       задана — собрать и опубликовать их (второй набор)
set -euo pipefail

: "${S3_ENDPOINT:?задайте S3_ENDPOINT}"
BUCKET="${MIRROR_BUCKET:-mirror}"
MANIFEST="${MIRROR_MANIFEST:-/scripts/artifacts.tsv}"
SCHEMA_REPO="${SCHEMA_REPO:-https://github.com/yannh/kubernetes-json-schema.git}"
CRD_SCHEMA_REPO="${CRD_SCHEMA_REPO:-https://github.com/datreeio/CRDs-catalog.git}"

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
#
# Набора два: standalone и standalone-strict. Второй нужен гейту с флагом
# -strict: kubeconform подставляет {{.StrictSuffix}} в путь и ищет схему в
# каталоге, которого в зеркале не было бы. Оба кладём из одного клона, меняя
# sparse-checkout, чтобы не платить за clone дважды.
#
# Имя объекта — kubernetes-json-schema_<ver>_<variant>.tar.gz, где variant это
# standalone или standalone-strict; внутри архива каталог v<ver>-<variant>.
# Разделитель в имени и в каталоге разный, и это не опечатка: так объекты
# лежали до появления второго набора, переименование ломает ссылки в CI.
sync_schemas() {
  local ver="$1" tmp
  [ -z "$ver" ] && return 0

  local -a pending=()
  local variant dir path
  for variant in "standalone" "standalone-strict"; do
    dir="v${ver}-${variant}"
    path="kubeconform-schemas/$ver/kubernetes-json-schema_${ver}_${variant}.tar.gz"
    if object_exists "$path"; then
      echo "skip $path"
    else
      pending+=("$variant")
    fi
  done
  [ "${#pending[@]}" -eq 0 ] && return 0

  ensure_build_tools
  tmp="$(mktemp -d)"
  git clone --depth 1 --filter=blob:none --sparse "$SCHEMA_REPO" "$tmp/schemas"
  for variant in "${pending[@]}"; do
    dir="v${ver}-${variant}"
    git -C "$tmp/schemas" sparse-checkout set "$dir"
    echo "build kubeconform-schemas/$ver/kubernetes-json-schema_${ver}_${variant}.tar.gz"
    tar -C "$tmp/schemas" \
      --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
      -czf "$tmp/schemas.tar.gz" "$dir"
    s3cp "$tmp/schemas.tar.gz" "s3://$BUCKET/kubeconform-schemas/$ver/kubernetes-json-schema_${ver}_${variant}.tar.gz"
  done
  rm -rf "$tmp"
}

# Схемы CR лежат в каталоге datreeio/CRDs-catalog как <group>/<kind>_<version>.json,
# готовых архивов нет — кладём весь каталог одним объектом. Он небольшой, а
# перечисление используемых групп в манифесте пришлось бы вести вручную и
# забывать: забытая группа означает красный гейт на новом CRD.
#
# Ревизия зафиксирована коммитом и совпадает с CRD_SCHEMAS_REV в
# scripts/kubeconform.sh. Fetch по SHA, а не shallow clone ветки: у каталога
# нет пригодных тегов, а main движется каждый день.
#
# Имя объекта повторяет схему Kubernetes-схем, включая непривычный разделитель:
# crds-catalog_<rev>.tar.gz внутри каталога без префикса, чтобы распаковка в
# ~/.cache/kubeconform-schemas давала готовый путь crds/<group>/<kind>_<version>.json.
sync_cr_schemas() {
  local rev="$1" path tmp
  [ -z "$rev" ] && return 0

  path="kubeconform-cr-schemas/$rev/crds-catalog_${rev}.tar.gz"
  if object_exists "$path"; then
    echo "skip $path"
    return 0
  fi

  ensure_build_tools
  tmp="$(mktemp -d)"
  git init -q "$tmp/crds"
  git -C "$tmp/crds" remote add origin "$CRD_SCHEMA_REPO"
  # GitHub отдаёт коммит по SHA через fetch, shallow достаточно: история не нужна.
  git -C "$tmp/crds" fetch -q --depth 1 origin "$rev"
  git -C "$tmp/crds" checkout -q FETCH_HEAD
  echo "build $path"
  # Каталог .git не попадает в архив, mtime и владелец фиксированы, иначе
  # одинаковая ревизия давала бы разные байты при каждом прогоне.
  tar -C "$tmp/crds" \
    --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --exclude=.git \
    -czf "$tmp/crds.tar.gz" .
  mkdir -p "kubeconform-cr-schemas/$rev"
  s3cp "$tmp/crds.tar.gz" "s3://$BUCKET/$path"
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

if [ -n "${CRD_SCHEMAS_REV:-}" ]; then
  if ! sync_cr_schemas "$CRD_SCHEMAS_REV"; then
    failed+=("kubeconform-cr-schemas/$CRD_SCHEMAS_REV")
  fi
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo "mirror sync finished with ${#failed[@]} failure(s):" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi

echo "mirror sync done"
