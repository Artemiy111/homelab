#!/usr/bin/env bash
# Список юнитов для clusters/casa/kustomization.yaml.
#
# Kustomize не раскрывает шаблоны в resources: литерал 'apps/*/app.yaml' уходит
# в lstat и валит сборку (проверено на 5.8.1, Argo рендерит тем же kustomize).
# Поэтому список явный, но не ручной — он генерируется из дерева, а
# scripts/check.sh проверяет, что файл соответствует дереву. Расхождение здесь
# не стилистика: молчаливое отсутствие Application означает, что сервис не
# задеплоится.
#
#   ./scripts/argocd-units.sh              напечатать блок resources
#   ./scripts/argocd-units.sh > clusters/casa/kustomization.yaml
#   ./scripts/argocd-units.sh --check      проверить, что файл актуален
#
# Сортировка по имени каталога: порядок в Application не значит ничего (root
# синкает пачкой), а детерминированный порядок нужен, чтобы diff не дрожал.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

emit() {
  cat <<'HEADER'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Сгенерировано ./scripts/argocd-units.sh — правь скрипт, не этот файл.
HEADER
  echo "resources:"
  {
    for project in clusters/casa/projects/*.yaml; do
      [ -e "$project" ] || continue
      echo "  - projects/$(basename "$project")"
    done
    for spec in clusters/casa/platform/*/app.yaml; do
      [ -e "$spec" ] || continue
      echo "  - platform/$(basename "$(dirname "$spec")")/app.yaml"
    done
    for spec in clusters/casa/apps/*/app.yaml; do
      [ -e "$spec" ] || continue
      echo "  - apps/$(basename "$(dirname "$spec")")/app.yaml"
    done
  } | sort -u
}

if [ "${1:-}" = "--check" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  emit > "$tmp"
  if diff -u clusters/casa/kustomization.yaml "$tmp"; then
    rm -f "$tmp"
    trap - EXIT
    echo "список юнитов соответствует дереву"
    exit 0
  fi
  echo "список юнитов разошёлся с деревом, перегенерируй:" >&2
  echo "  ./scripts/argocd-units.sh > clusters/casa/kustomization.yaml" >&2
  exit 1
fi

emit
