#!/usr/bin/env bash
# Генератор проверяемых чисел для README: docs/status/status.json и
# docs/status/badges/{en,ru}/*.svg. Считает только по содержимому
# репозитория — ни сети, ни времени, ни состояния кластера, — иначе гейт
# «перегенерируй и сравни» ловил бы сам себя.
#
#   ./scripts/status-badges.sh            перегенерировать артефакты
#   ./scripts/status-badges.sh --check    проверить, что артефакты в коммите свежие
#
# Скрипт не добавляет бинарей в тулчейн CI: только git, grep, awk и coreutils.
set -euo pipefail

# C локаль — не для вкуса: ширина текста в SVG считается по байтам, а русские
# подписи в UTF-8 это две байты на букву, и побайтовый проход по такой строке
# в локализованном awk падает на границе символа. Заодно sort и grep перестают
# зависеть от локали, то есть артефакты перестают зависеть от окружения.
export LC_ALL=C

root="$(git rev-parse --show-toplevel)"
status_dir="${root}/docs/status"
mode="write"

for arg in "$@"; do
  case "$arg" in
    --check) mode="check" ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "неизвестный аргумент: $arg" >&2
      exit 2
      ;;
  esac
done

cd "$root"

# Файлы репозитория: только индекс, без незакоммиченных. Число обязано быть
# функцией от того, что попадёт в коммит: иначе локальный мусор в рабочем дереве
# двигает бейдж, которого в CI не существует. Новый файл попадает в счёт после
# `git add` — этого достаточно, потому что pre-commit хук запускается после
# индексации.
repo_files() {
  git ls-files --exclude-standard "$@"
}

# Две области, и разница между ними осмысленная.
#
# deploy_files — всё, что уезжает в кластер: любой отслеживаемый YAML под
# clusters/casa/apps/, clusters/casa/platform/, argocd/, включая values.yaml, чарты сервисов и шаблоны
# чарта homelab. Compose-файлы хостовых утилит (clusters/casa/apps/spotdl) в кластер не
# попадают, поэтому исключены. По этой области считаются образы, namespace'ы и
# секреты.
deploy_files() {
  repo_files '*.yaml' '*.yml' |
    grep -E '^(clusters/casa/apps|clusters/casa/platform|argocd)/' |
    grep -vE '/compose\.ya?ml$' || true
}

# manifest_files — область CI-гейта kubeconform: clusters/casa/apps/<сервис>/manifests/, clusters/casa/platform/,
# argocd/ без values.yaml, Chart.yaml и шаблонов чарта. Только по ней считается
# число манифестов, чтобы оно совпадало с тем, что реально проверяет CI.
manifest_files() {
  repo_files '*.yaml' '*.yml' |
    grep -E '^(clusters/casa/apps/[^/]+/manifests|clusters/casa/platform|argocd)/' |
    grep -vE '(values|Chart)\.yaml$' |
    grep -vE '^clusters/casa/platform/homelab/templates/' |
    grep -vE '/manifests/config/' || true
}

# Образ в однострочной форме `image: <ref>`. Многострочные формы (`image:` и
# ниже отдельный `repository`/`tag`, как в CNPG и в чартах Argo) в знаменатель
# не идут: их нельзя объявить «не закреплёнными» без разбора YAML, а выпадать
# они могут и с digest'ом.
image_lines() {
  deploy_files | xargs grep -hE '^[[:space:]]*image:[[:space:]]*[^[:space:]]' || true
}

count_lines() {
  grep -c '' || true
}

# JSON-массив из строк на входе: наружу уходят только имена файлов и
# namespace'ов, ни адресов, ни значений.
json_array() {
  awk 'BEGIN { printf "[" } { printf "%s\"%s\"", (NR == 1 ? "" : ", "), $0 } END { print "]" }'
}

services="$(repo_files 'clusters/casa/apps/*.yaml' 'clusters/casa/apps/*.yml' | cut -d/ -f4 | sort -u | count_lines)"
manifests="$(manifest_files | count_lines)"
images_pinned="$(image_lines | grep -cE '@sha256:' || true)"
images_total="$(image_lines | count_lines)"
if [ "$images_total" -eq 0 ]; then
  echo "не найдено ни одного image: в области deploy_files — метод подсчёта сломан" >&2
  exit 1
fi
images_percent=$((images_pinned * 100 / images_total))
images_exceptions="$(
  deploy_files |
    xargs grep -nE '^[[:space:]]*image:[[:space:]]*[^[:space:]]' |
    grep -v '@sha256:' |
    cut -d: -f1 |
    sort -u || true
)"

# namespace из `metadata.namespace` (отступ 2, формат kubiform) и из
# `spec.destination.namespace` у Application (отступ 4 под секцией
# `destination:`). Второй источник нужен: иначе операторы, у которых в
# репозитории есть только Application, выпадали бы из знаменателя и покрытие
# завышалось бы. Вложенные `namespace:` из subject'ов RBAC и service-ссылок
# вебхуков не считаются: у них отступ 2, но перед ними `-`.
#
# awk получает файлы целиком, а не отфильтрованные строки `namespace:`:
# признак «сейчас секция destination» виден только в соседних строках.
namespace_names() {
  deploy_files |
    xargs awk '
      /^  namespace: [a-z0-9-]+$/ { print $2; next }
      /^    namespace: [a-z0-9-]+$/ && section == "destination" { print $2; next }
      /^  [a-zA-Z0-9_-]+:/ { section = $1; sub(/:$/, "", section) }
    ' |
    sort -u || true
}

netpol_files() {
  deploy_files | xargs grep -lE '^kind: NetworkPolicy$' || true
}

netpol_namespaces() {
  netpol_files |
    xargs awk '
      /^  namespace: [a-z0-9-]+$/ { print $2; next }
      /^    namespace: [a-z0-9-]+$/ && section == "destination" { print $2; next }
      /^  [a-zA-Z0-9_-]+:/ { section = $1; sub(/:$/, "", section) }
    ' |
    sort -u || true
}

namespaces_total="$(namespace_names | count_lines)"
netpol_namespaces_total="$(netpol_namespaces | count_lines)"
netpol_percent=$((netpol_namespaces_total * 100 / namespaces_total))
netpol_exceptions="$(comm -23 <(namespace_names) <(netpol_namespaces))"
netpol_objects="$(deploy_files | xargs grep -hE '^kind: NetworkPolicy$' | count_lines)"

vault_static="$(deploy_files | xargs grep -hE '^kind: VaultStaticSecret$' | count_lines)"
sealed="$(deploy_files | xargs grep -hE '^kind: SealedSecret$' | count_lines)"

adr="$(repo_files 'docs/adr/*.md' | grep -v '/README.md$' | count_lines)"
postmortems="$(repo_files 'docs/incidents/*.md' | grep -cE '/[0-9]{4}-' || true)"
research="$(repo_files 'docs/research/*.md' 'docs/research/**/*.md' | count_lines)"

# SVG в стиле shields: плоский, с тёмной темой через prefers-color-scheme.
# Ширина текста считается по таблице символов — достаточно, чтобы подпись
# не обрезалась; вложенный <style> переживает GitHub и camo.
render_badge() {
  local label="$1" message="$2" color="$3"
  awk -v label="$label" -v message="$message" -v color="$color" '
    function esc(s) {
      gsub(/&/, "\\&amp;", s)
      gsub(/</, "\\&lt;", s)
      gsub(/>/, "\\&gt;", s)
      return s
    }
    function width(s,   i, c, w) {
      w = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c ~ /[^ -~]/) w += 3.9
        else if (c == "/" || c == "\\") w += 4.5
        else if (c == " " || c ~ /[.,;:!|iljft]/) w += 3.9
        else if (c ~ /[mw]/) w += 9.6
        else if (c == "%") w += 10.0
        else if (c ~ /[A-Z]/) w += 8.4
        else if (c ~ /[0-9]/) w += 7.4
        else w += 6.8
      }
      return w
    }
    BEGIN {
      lw = int(width(label)) + 12
      vw = int(width(message)) + 12
      title = esc(label ": " message)
      printf("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"20\" role=\"img\" aria-label=\"%s\">\n", lw + vw, title)
      printf("  <title>%s</title>\n", title)
      printf("  <style>rect.label-bg{fill:#555}@media (prefers-color-scheme:dark){rect.label-bg{fill:#3f3f3f}}text{font-family:Verdana,DejaVu Sans,Geneva,sans-serif;font-size:11px;fill:#fff}</style>\n")
      printf("  <rect class=\"label-bg\" width=\"%d\" height=\"20\"/>\n", lw)
      printf("  <rect x=\"%d\" width=\"%d\" height=\"20\" fill=\"%s\"/>\n", lw, vw, color)
      printf("  <text x=\"%d\" y=\"14\" text-anchor=\"middle\">%s</text>\n", int(lw / 2), esc(label))
      printf("  <text x=\"%d\" y=\"14\" text-anchor=\"middle\">%s</text>\n", lw + int(vw / 2), esc(message))
      printf("</svg>\n")
    }
  '
}

# Цвет — это вердикт, а не украшение: бейдж должен краснеть, когда число
# ухудшается, иначе он ничего не проверяет.
color_at_least() {
  local value="$1" good="$2" ok="$3"
  if [ "$value" -ge "$good" ]; then printf '%s' '#4c1'
  elif [ "$value" -ge "$ok" ]; then printf '%s' '#dfb317'
  else printf '%s' '#e05d44'
  fi
}

write_artifacts() {
  local out="$1"
  mkdir -p "${out}/badges/en" "${out}/badges/ru"

  local pinned_color netpol_color
  pinned_color="$(color_at_least "$images_percent" 95 80)"
  netpol_color="$(color_at_least "$netpol_percent" 95 85)"

  local en_label_services="services" ru_label_services="сервисов"
  local en_label_manifests="manifests" ru_label_manifests="манифестов"
  local en_label_pinned="images pinned" ru_label_pinned="образов на digest"
  local en_label_netpol="netpol coverage" ru_label_netpol="namespace с netpol"
  local en_label_adr="ADRs" ru_label_adr="ADR"
  local en_label_pm="postmortems" ru_label_pm="постмортемов"

  render_badge "$en_label_services" "$services" '#007ec6' >"${out}/badges/en/services.svg"
  render_badge "$ru_label_services" "$services" '#007ec6' >"${out}/badges/ru/services.svg"
  render_badge "$en_label_manifests" "$manifests" '#007ec6' >"${out}/badges/en/manifests.svg"
  render_badge "$ru_label_manifests" "$manifests" '#007ec6' >"${out}/badges/ru/manifests.svg"
  render_badge "$en_label_pinned" "${images_percent}%" "$pinned_color" >"${out}/badges/en/images-pinned.svg"
  render_badge "$ru_label_pinned" "${images_percent}%" "$pinned_color" >"${out}/badges/ru/images-pinned.svg"
  render_badge "$en_label_netpol" "${netpol_namespaces_total}/${namespaces_total}" "$netpol_color" >"${out}/badges/en/netpol-coverage.svg"
  render_badge "$ru_label_netpol" "${netpol_namespaces_total}/${namespaces_total}" "$netpol_color" >"${out}/badges/ru/netpol-coverage.svg"
  render_badge "$en_label_adr" "$adr" '#007ec6' >"${out}/badges/en/adr.svg"
  render_badge "$ru_label_adr" "$adr" '#007ec6' >"${out}/badges/ru/adr.svg"
  render_badge "$en_label_pm" "$postmortems" '#007ec6' >"${out}/badges/en/postmortems.svg"
  render_badge "$ru_label_pm" "$postmortems" '#007ec6' >"${out}/badges/ru/postmortems.svg"

  cat >"${out}/status.json" <<JSON
{
  "schema": 1,
  "source": "scripts/status-badges.sh",
  "services": $services,
  "manifests": $manifests,
  "images": {
    "pinned": $images_pinned,
    "total": $images_total,
    "percent": $images_percent,
    "exceptions": $(printf '%s' "$images_exceptions" | json_array)
  },
  "network_policy": {
    "objects": $netpol_objects,
    "namespaces": $netpol_namespaces_total,
    "namespaces_total": $namespaces_total,
    "percent": $netpol_percent,
    "exceptions": $(printf '%s' "$netpol_exceptions" | json_array)
  },
  "secrets": {
    "vault_static_secret": $vault_static,
    "sealed_secret": $sealed
  },
  "docs": {
    "adr": $adr,
    "postmortems": $postmortems,
    "research": $research
  }
}
JSON
}

case "$mode" in
  write)
    write_artifacts "$status_dir"
    echo "обновлено: docs/status/status.json, docs/status/badges/{en,ru}"
    ;;
  check)
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    write_artifacts "$tmp"
    stale=0
    if ! diff -q "$status_dir/status.json" "$tmp/status.json" >/dev/null; then
      diff -u "$status_dir/status.json" "$tmp/status.json" >&2 || true
      stale=1
    fi
    if ! diff -r -q "$status_dir/badges" "$tmp/badges" >/dev/null; then
      diff -r -q "$status_dir/badges" "$tmp/badges" >&2 || true
      stale=1
    fi
    if [ "$stale" -ne 0 ]; then
      echo "docs/status разошёлся с репозиторием" >&2
      echo "исправь: ./scripts/status-badges.sh && git add docs/status" >&2
      exit 1
    fi
    echo "docs/status в актуальном состоянии"
    ;;
esac
