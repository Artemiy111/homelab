#!/usr/bin/env bash
# Проверка манифестов kubeconform. Один набор путей, схем и фильтров для
# .githooks/pre-commit, локального scripts/check.sh и гейта
# .forgejo/workflows/kubeconform.yml: расхождение между ними хуже, чем
# отсутствие проверки, потому что локально зелёный прогон, красный в CI,
# приучает не смотреть на результат.
#
#   ./scripts/kubeconform.sh             все каталоги с манифестами
#   ./scripts/kubeconform.sh path/...    только перечисленные файлы
#
# Без аргументов проверяются каталоги гейта, с аргументами — ровно то, что
# передали: так pre-commit смотрит на staged, а не перебирает дерево целиком.
#
# Бинарь ставит вызывающий: хук и check.sh останавливают коммит или печатают
# предупреждение, если kubeconform не установлен, workflow берёт его из зеркала
# RustFS. Схемы Kubernetes, наоборот, берёт сам — из локального набора, если он
# есть, иначе по сети той же версии.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

if ! command -v kubeconform >/dev/null 2>&1; then
  echo "kubeconform не установлен (brew install kubeconform)" >&2
  exit 1
fi

# Версия Kubernetes и ревизия каталога CRD — те же, что в CI. CRD_SCHEMAS_REV
# остаётся переменной окружения: ею ключуется кэш схем в workflow, и там её
# значение обязано совпадать с дефолтом здесь.
kube_version="1.36.3"
crd_catalog_rev="${CRD_SCHEMAS_REV:-fd90051867733c60d32d16450556e9cd18459aef}"
schema_dir="${KUBECONFORM_SCHEMA_DIR:-$HOME/.cache/kubeconform-schemas}"
cache_dir="${KUBECONFORM_CACHE_DIR:-$HOME/.cache/kubeconform-http}"

mkdir -p "$cache_dir"

# Схемы Kubernetes: локальный набор, если он есть, иначе monorepo. Оба
# -schema-location нужны, потому что kubeconform берёт первую, что ответила: в
# CI зеркало RustFS (issue #149) публикует только нестрогий набор
# v${ver}-standalone, а -strict меняет имя каталога на v${ver}-standalone-strict,
# и запрос в зеркало уходит в 404. Локально набора нет вовсе. Порядок не важен,
# важно, что оба источника названы и версия в пути зафиксирована: набор схем не
# «уезжает» вместе с веткой master.
k8s_schema_name="{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json"
k8s_schema_locations=(
  "$schema_dir/$k8s_schema_name"
  "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/$k8s_schema_name"
)

# Набор CR кладёт зеркало: весь каталог одним объектом, распакованный в
# $schema_dir/crds. GitHub остаётся в списке последним — локально набор обычно не
# скачан, и без него проверка не работает вовсе, а в CI зеркало отвечает первым
# и недостижимый GitHub просто не опрашивается (#910).
crd_schema_name="{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# Набор CR — из datreeio/CRDs-catalog: они не входят в схемы Kubernetes, а без
# них не проверялись бы все kind'ы операторов (HTTPRoute, Application,
# VaultStaticSecret и прочие). Ревизия зафиксирована коммитом: у каталога нет
# пригодных тегов, а ветка main движется каждый день, и без пина красный job
# нельзя отличить от «схему обновили полчаса назад».
#
# -cache складывает скачанные схемы на диск: иначе каждый прогон тянет
# несколько сотен файлов заново.
#
# Фильтры: values.yaml и Chart.yaml — не манифесты, templates чарта homelab
# рендерится (отдельная задача), kustomization.yaml — вход для kustomize, а не
# объект API.
#
# -strict включает запрет неизвестных полей. Без него опечатка в имени поля
# проходит молча: для ConfigMap это безобидно, для CR оператора — расхождение с
# CRD, которое переживёт ревью незамеченным. Схемы CR из каталога строгие уже
# по построению, strict касается схем Kubernetes.
#
# Сканируются каталоги с манифестами: clusters/casa/apps/<сервис>/manifests, clusters/casa/platform, bootstrap. Внутри manifests лежит config/ — это конфиги
# приложений, а не манифесты, поэтому исключены по пути.
# -ignore-missing-schemas намеренно не используется: для kind'а, которому нет
# схемы, лучше упасть, чем пройти молча.
if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=(clusters/casa/apps/*/manifests clusters/casa/platform bootstrap)
fi

schema_args=()
for location in "${k8s_schema_locations[@]}"; do
  schema_args+=(-schema-location "$location")
done

schema_args+=(-schema-location "$schema_dir/crds/$crd_schema_name")
schema_args+=(
  -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/$crd_catalog_rev/$crd_schema_name"
)

kubeconform \
  -strict \
  -kubernetes-version "$kube_version" \
  -cache "$cache_dir" \
  "${schema_args[@]}" \
  -ignore-filename-pattern 'values\.yaml$' \
  -ignore-filename-pattern 'Chart\.yaml$' \
  -ignore-filename-pattern 'manifests/config/' \
  -ignore-filename-pattern 'kustomization\.yaml$' \
  -summary \
  "${targets[@]}"