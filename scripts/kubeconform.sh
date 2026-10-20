#!/usr/bin/env bash
# Проверка манифестов kubeconform. Один набор путей, схем и фильтров для
# .githooks/pre-commit, локального scripts/check.sh и гейта
# .forgejo/workflows/030-kubeconform.yml: расхождение между ними хуже, чем
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
# RustFS. Схемы скрипт берёт из локального набора, а если его нет — по сети той
# же версии; KUBECONFORM_OFFLINE=1 запрещает сеть совсем.
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
# Гейт выставляет KUBECONFORM_OFFLINE=1: наборы схем он раскладывает сам, и
# проверка не должна зависеть от внешнего DNS и доступности
# raw.githubusercontent.com. Локально и в хуках режим выключен — наборов там
# обычно нет, и без HTTP проверка не работает вовсе.
offline="${KUBECONFORM_OFFLINE:-0}"

mkdir -p "$cache_dir"

# Схемы Kubernetes: локальный набор из зеркала (workflow раскладывает оба,
# standalone и standalone-strict: при -strict в пути есть суффикс), иначе
# monorepo той же версии. Версия в пути зафиксирована, поэтому набор схем не
# «уезжает» вместе с веткой master.
k8s_schema_name="{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json"
k8s_local_schema="$schema_dir/$k8s_schema_name"
k8s_remote_schema="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/$k8s_schema_name"

# Набор CR кладёт зеркало: весь каталог одним архивом, распакованный в
# $schema_dir/crds. Каталог datreeio/CRDs-catalog нужен потому, что CR-видов нет
# в схемах Kubernetes, а без них не проверялись бы все kind'ы операторов
# (HTTPRoute, Application, VaultStaticSecret и прочие). Ревизия зафиксирована
# коммитом: у каталога нет пригодных тегов, а ветка main движется каждый день, и
# без пина красный job нельзя отличить от «схему обновили полчаса назад».
crd_schema_name="{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
crd_local_schema="$schema_dir/crds/$crd_schema_name"
crd_remote_schema="https://raw.githubusercontent.com/datreeio/CRDs-catalog/$crd_catalog_rev/$crd_schema_name"

if [ "$offline" = "1" ]; then
  for dir in "$schema_dir/v$kube_version-standalone-strict" "$schema_dir/crds"; do
    if [ ! -d "$dir" ]; then
      echo "нет локального набора схем: $dir (KUBECONFORM_OFFLINE=1 запрещает HTTP)" >&2
      exit 1
    fi
  done
fi

# Фильтры: values.yaml и Chart.yaml — не манифесты, templates чарта homelab
# рендерится (отдельная задача), kustomization.yaml — вход для kustomize, а не
# объект API.
#
# -strict включает запрет неизвестных полей. Без него опечатка в имени поля
# проходит молча: для ConfigMap это безобидно, для CR оператора — расхождение с
# CRD, которое переживёт ревью незамеченным. Схемы CR из каталога строгие уже
# по построению, strict касается схем Kubernetes.
#
# Сканируются каталоги с манифестами: apps/casa/<сервис>/manifests, platform/casa, clusters/casa/argocd. Внутри manifests лежит config/ — это конфиги
# приложений, а не манифесты, поэтому исключены по пути.
# -ignore-missing-schemas намеренно не используется: для kind'а, которому нет
# схемы, лучше упасть, чем пройти молча.
if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=(apps/casa/*/manifests platform/casa clusters/casa/argocd)
fi

# Порядок источников — часть контракта, а не оформление. kubeconform прекращает
# поиск на первой ошибке, которая не 404 (pkg/validator, downloadSchema),
# поэтому сетевой источник перед локальным роняет ресурс даже когда схема лежит
# на диске. С локальными первыми здоровый прогон не опрашивает сеть, а в
# офлайн-режиме HTTP-источников в списке нет вовсе.
#
# -cache складывает скачанные схемы на диск: в сетевом режиме без него каждый
# прогон тянет несколько сотен файлов заново.
schema_args=(
  -schema-location "$k8s_local_schema"
  -schema-location "$crd_local_schema"
)
if [ "$offline" != "1" ]; then
  schema_args+=(
    -schema-location "$k8s_remote_schema"
    -schema-location "$crd_remote_schema"
  )
fi

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
