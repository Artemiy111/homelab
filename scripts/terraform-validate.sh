#!/usr/bin/env bash
# Валидация Terraform-модулей: init -backend=false и validate для каждого
# root-модуля в infra/casa/terraform и infra/global/terraform, и для дочернего
# vault/policies.
#
#   ./scripts/terraform-validate.sh
#
# Работа идёт на копии отслеживаемых файлов, а не в рабочем дереве: init
# дописывает в lock-файл h1-хэш платформы, на которой идёт установка, и
# править lock-файл репозитория проверка не должна.
#
# Два режима, различаются только источником провайдеров:
#
#   PROVIDER_MIRROR_URL задан — провайдеры берутся из зеркала (внутрикластерный
#     CI: с раннера нет интернета, а реестр Terraform к тому же режет запросы по
#     геолокации). init ходит в файловый mirror, direct исключён, иначе
#     провайдер, которого нет в зеркале, ушёл бы в реестр вместо падения.
#   PROVIDER_MIRROR_URL не задан — init ходит в реестр напрямую (GitHub-раннер).
#
# Целостность архива проверяется по zh:-хэшам lock-файла: это sha256 zip-а для
# каждой платформы, которую публикует провайдер, и linux_amd64 в списке есть.
# h1:-хэши относятся к платформе, на которой lock-файл создан (у нас — macOS), и
# на целевой платформе init дописывает их сам — в копии, не в репозитории.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

mirror_url="${PROVIDER_MIRROR_URL:-}"
mirror_dir="${PROVIDER_MIRROR_DIR:-$HOME/.cache/terraform-provider-mirror}"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform не установлен (brew install terraform)" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Копия отслеживаемых файлов: .terraform-каталоги и state не копируются, а
# lock-файлы нужны — по ним выбираются версии провайдеров.
while IFS= read -r -d '' file; do
  mkdir -p "$work/$(dirname "$file")"
  cp "$file" "$work/$file"
done < <(git ls-files -z "infra/casa/terraform" "infra/global/terraform")

# Root-модули — те, у кого есть lock-файл: без него версии провайдеров не
# зафиксированы, и init тянет реестр напрямую.
modules=()
for d in "$work"/infra/casa/terraform/*/ "$work"/infra/global/terraform/*/; do
  [ -f "$d.terraform.lock.hcl" ] && modules+=("${d%/}")
done
if [ "${#modules[@]}" -eq 0 ]; then
  echo "не найдено ни одного модуля с .terraform.lock.hcl" >&2
  exit 1
fi

if [ -n "$mirror_url" ]; then
  rm -rf "$mirror_dir"
  mkdir -p "$mirror_dir"
  while read -r addr ver hashes; do
    if [ -z "$addr" ] || [ -z "$ver" ]; then
      continue
    fi
    type="${addr##*/}"
    fname="terraform-provider-${type}_${ver}_linux_amd64.zip"
    dir="$mirror_dir/$addr"
    mkdir -p "$dir"
    if ! curl -fsSL -o "$dir/$fname" "$mirror_url/providers/$addr/$fname"; then
      echo "провайдер не скачался из зеркала: $addr $ver" >&2
      exit 1
    fi
    got="$(sha256sum "$dir/$fname" | awk '{print $1}')"
    if ! printf ' %s ' "$hashes" | grep -q " $got "; then
      echo "sha256 архива не входит в zh-хэши lock-файла: $addr $ver" >&2
      exit 1
    fi
  done < <(
    for d in "${modules[@]}"; do
      cat "$d/.terraform.lock.hcl"
    done | awk '
      $1 == "provider" { addr = $2; gsub(/"/, "", addr); ver = ""; hashes = ""; next }
      addr != "" && $1 == "version" { ver = $3; gsub(/"/, "", ver); next }
      addr != "" && /"zh:/ {
        line = $0; gsub(/[" ,]/, "", line); sub(/^zh:/, "", line); hashes = hashes " " line; next
      }
      addr != "" && $0 == "}" {
        if (ver != "") print addr "\t" ver "\t" hashes
        addr = ""
      }')
fi

# Каталог с провайдерами: filesystem_mirror вместо network_mirror, потому что
# последний требует https, а зеркало отдаётся по http. direct исключён —
# иначе провайдер, которого нет в зеркале, ушёл бы в реестр вместо падения.
if [ -n "$mirror_url" ]; then
  tfrc="$work/terraformrc"
  cat > "$tfrc" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "$mirror_dir"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
EOF
  export TF_CLI_CONFIG_FILE="$tfrc"
fi

status=0
for module in "${modules[@]}"; do
  echo "== ${module#"$work"/}"
  if ! terraform -chdir="$module" init -backend=false >/dev/null; then
    echo "init не прошёл: ${module#"$work"/}" >&2
    status=1
    continue
  fi
  if ! terraform -chdir="$module" validate; then
    echo "validate не прошёл: ${module#"$work"/}" >&2
    status=1
  fi
done

# Дочерний модуль проверяется отдельно: lock-файла у него нет, и init создал бы
# его в дереве репозитория. Lock-файл родителя копируется рядом, чтобы версия
# провайдера совпала с зафиксированной в корневых модулях, а не была выбрана
# заново.
child="$work/infra/casa/terraform/vault/policies"
if [ -d "$child" ]; then
  echo "== infra/casa/terraform/vault/policies"
  cp "$work/infra/casa/terraform/vault/.terraform.lock.hcl" "$child/.terraform.lock.hcl"
  if ! terraform -chdir="$child" init -backend=false >/dev/null; then
    echo "init не прошёл: infra/casa/terraform/vault/policies" >&2
    status=1
  elif ! terraform -chdir="$child" validate; then
    echo "validate не прошёл: infra/casa/terraform/vault/policies" >&2
    status=1
  fi
fi

exit "$status"
