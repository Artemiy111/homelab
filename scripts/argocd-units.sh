#!/usr/bin/env bash
# Список юнитов для clusters/<кластер>/argocd/kustomization.yaml.
#
# Kustomize не раскрывает шаблоны в resources: литерал 'apps/*.yaml' уходит
# в lstat и валит сборку (проверено на 5.8.1, Argo рендерит тем же kustomize).
# Поэтому список явный, но не ручной — он генерируется из дерева, а
# scripts/check.sh проверяет, что файл соответствует дереву. Расхождение здесь
# не стилистика: молчаливое отсутствие Application означает, что сервис не
# задеплоится.
#
#   ./scripts/argocd-units.sh                     напечатать блок resources для casa
#   ./scripts/argocd-units.sh <кластер>           то же для другого кластера
#   ./scripts/argocd-units.sh > clusters/casa/argocd/kustomization.yaml
#   ./scripts/argocd-units.sh --check             проверить, что файл актуален
#
# Сортировка по имени файла: порядок в Application не значит ничего (root
# синкает пачкой), а детерминированный порядок нужен, чтобы diff не дрожал.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

cluster="casa"
mode="write"

for arg in "$@"; do
  case "$arg" in
    --check) mode="check" ;;
    -h | --help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "неизвестный аргумент: $arg" >&2
      exit 2
      ;;
    *) cluster="$arg" ;;
  esac
done

argocd="clusters/$cluster/argocd"
kustomization="$argocd/kustomization.yaml"

emit() {
  cat <<'HEADER'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Сгенерировано ./scripts/argocd-units.sh — правь скрипт, не этот файл.
HEADER
  echo "resources:"
  {
    for project in "$argocd"/appprojects/*.yaml; do
      [ -e "$project" ] || continue
      echo "  - appprojects/$(basename "$project")"
    done
    for spec in "$argocd"/platform/*.yaml; do
      [ -e "$spec" ] || continue
      echo "  - platform/$(basename "$spec")"
    done
    for spec in "$argocd"/apps/*.yaml; do
      [ -e "$spec" ] || continue
      echo "  - apps/$(basename "$spec")"
    done
  } | sort -u
}

if [ "$mode" = "check" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  emit >"$tmp"
  if diff -u "$kustomization" "$tmp"; then
    rm -f "$tmp"
    trap - EXIT
    echo "список юнитов соответствует дереву"
    exit 0
  fi
  echo "список юнитов разошёлся с деревом, перегенерируй:" >&2
  echo "  ./scripts/argocd-units.sh > $kustomization" >&2
  exit 1
fi

emit
