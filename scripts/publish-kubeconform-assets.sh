#!/usr/bin/env bash
#
# Публикует артефакты для CI-джобы kubeconform в Forgejo generic packages:
#   - kubeconform (linux/amd64) — сам валидатор;
#   - kubeconform-schemas — набор OpenAPI-схем Kubernetes (standalone) для
#     фиксированной версии.
# Раннер не ходит на github.com, поэтому артефакты хостятся на Forgejo и
# скачиваются из job'ов анонимно (см. .forgejo/workflows/kubeconform.yml).
#
# Запуск (нужен PAT со scope write:package):
#   FORGEJO_URL=https://forgejo.example.com FORGEJO_TOKEN=... \
#     scripts/publish-kubeconform-assets.sh
#
# Версии по умолчанию совпадают с workflow; при апгрейде Kubernetes меняется
# KUBERNETES_VERSION (и её надо синхронно обновить в workflow).
set -euo pipefail

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.36.3}"
KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-0.8.0}"
FORGEJO_OWNER="${FORGEJO_OWNER:-artemiy}"
SCHEMA_REPO="${SCHEMA_REPO:-https://github.com/yannh/kubernetes-json-schema.git}"

: "${FORGEJO_URL:?задайте FORGEJO_URL, например https://forgejo.example.com}"
: "${FORGEJO_TOKEN:?задайте FORGEJO_TOKEN (PAT со scope write:package)}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

api="${FORGEJO_URL}/api/packages/${FORGEJO_OWNER}/generic"

# Forgejo не перезаписывает файл с тем же именем (409), поэтому версию пакета
# удаляем перед загрузкой. 404 (пакета ещё нет) — нормальный случай.
delete_version() {
  curl -s -o /dev/null -X DELETE -H "Authorization: token ${FORGEJO_TOKEN}" \
    "${api}/$1/$2"
}

kubeconform_asset="kubeconform_${KUBECONFORM_VERSION}_linux_amd64.tar.gz"
delete_version kubeconform "$KUBECONFORM_VERSION"
curl -fsSL -o "$workdir/$kubeconform_asset" \
  "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"
curl -fsS -X PUT --upload-file "$workdir/$kubeconform_asset" \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  "${FORGEJO_URL}/api/packages/${FORGEJO_OWNER}/generic/kubeconform/${KUBECONFORM_VERSION}/${kubeconform_asset}"
echo "published kubeconform ${KUBECONFORM_VERSION}"

schemas_asset="kubernetes-json-schema_${KUBERNETES_VERSION}_standalone.tar.gz"
delete_version kubeconform-schemas "$KUBERNETES_VERSION"
git clone --depth 1 --filter=blob:none --sparse "$SCHEMA_REPO" "$workdir/schemas"
git -C "$workdir/schemas" sparse-checkout set "v${KUBERNETES_VERSION}-standalone"
# COPYFILE_DISABLE/--no-xattrs: иначе bsdtar на macOS кладёт в архив расширенные
# атрибуты (com.apple.provenance), и GNU tar при распаковке в CI сыплет
# "Ignoring unknown extended header keyword".
COPYFILE_DISABLE=1 tar --no-xattrs -C "$workdir/schemas" -czf "$workdir/$schemas_asset" "v${KUBERNETES_VERSION}-standalone"
curl -fsS -X PUT --upload-file "$workdir/$schemas_asset" \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  "${FORGEJO_URL}/api/packages/${FORGEJO_OWNER}/generic/kubeconform-schemas/${KUBERNETES_VERSION}/${schemas_asset}"
echo "published kubeconform-schemas ${KUBERNETES_VERSION}"
