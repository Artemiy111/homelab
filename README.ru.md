# Домашний сервер

**Домашняя платформа на Kubernetes, эксплуатируемая как production: шестьдесят сервисов, один оператор,
ни одного деплоя руками.** Фото и медиа, файлы, почта, чат и видеозвонки, идентификация, Git с CI,
секреты и мониторинг работают на однонодовом кластере k0s. Каждое изменение попадает в кластер через
Git и Argo CD, проходя те же проверки, что и перед релизом в продуктовой команде.

> English version: [`README.md`](README.md)

[![services](docs/status/badges/ru/services.svg)](docs/status/README.md)
[![manifests](docs/status/badges/ru/manifests.svg)](docs/status/README.md)
[![images pinned](docs/status/badges/ru/images-pinned.svg)](docs/status/README.md)
[![netpol coverage](docs/status/badges/ru/netpol-coverage.svg)](docs/status/README.md)
[![ADR](docs/status/badges/ru/adr.svg)](docs/adr/)
[![постмортемы](docs/status/badges/ru/postmortems.svg)](docs/incidents/)

Каждое число в бейджах считается из git и проверяется гейтом в CI, поэтому оно не может разойтись с
кодом ([как именно считаются](docs/status/README.md)).

## Что это демонстрирует

- **Платформа, а не набор контейнеров.** Один Gateway с wildcard-сертификатом на входе и один провайдер
  идентификации за ним: Zitadel по OIDC или oauth2-proxy для приложений без собственного входа. Когда у
  DNS-провайдера не нашлось ни solver'а для cert-manager, ни рабочей интеграции по RFC2136, я написал
  [вебхук для cert-manager](packages/cert-manager-webhook-dns01/) и по тегу публикую его образ и чарт в
  OCI-реестр.
- **GitOps с ревью через пулл-реквесты.** Argo CD синхронизирует кластер из git. Десяток гейтов в CI
  проверяет сообщения коммитов, секреты, линтеры, схемы и безопасность манифестов, политику prune в Argo и
  документирование алертов. Тот же набор запускается в кластере и на публичном зеркале GitHub. Локальные
  хуки отлавливают большую часть проблем до коммита.
- **Наблюдаемость.** Метрики, логи, трейсы и профили связаны между собой в Grafana. eBPF даёт трейсы и
  off-CPU профили приложениям, которые никто не инструментировал.
- **Обучение на инцидентах.** ADR фиксируют решения, blameless-постмортемы заканчиваются задачами в
  трекере, а правило алертинга без записи в RUNBOOK валит сборку.
- **Гигиена секретов и цепочки поставки.** Образы закреплены по digest, секреты приходят только из Vault,
  gitleaks работает на каждом push. Поэтому репозиторий можно публиковать как есть.

## Стек

- **Платформа и хранилище:** k0s, Argo CD, Traefik, cert-manager, Longhorn, Technitium DNS
- **Идентификация и секреты:** Zitadel, Vault
- **Данные:** CloudNativePG, MariaDB, RustFS
- **Git:** Forgejo
- **Мониторинг:** Grafana
- **Приложения:** Immich, Jellyfin, Navidrome, Nextcloud, Element, Stalwart,
  Paperless, Home Assistant, Open WebUI

У каждого юнита есть README и RUNBOOK рядом с манифестами: [`apps/casa/`](apps/casa/) и
[`platform/casa/`](platform/casa/).

## Известные пробелы

- **Нет HA.** Одна машина и нет кворума, поэтому PodDisruptionBudget был бы театром. По той же причине
  среды не разведены по namespace'ам ([ADR 0001](docs/adr/0001-namespace-ownership.md)).
- **Нет репетиции восстановления.** Снапшоты есть, бэкап описан, но восстановление ни разу не проверяли.
- **Нет SLO.** Алертинг симптомный, а не построен на error budgets.
- **Нет admission-контроллера политик.** NetworkPolicy пишутся руками, и ничто не мешает выкатить манифест
  без них.
- **State Terraform локальный**, без лока и обнаружения дрейфа.
- **Образы закреплены, но не подписаны.** Нет SBOM и проверки подписи, trivy работает только в режиме отчёта.

Глубже: [`docs/adr/`](docs/adr/) — решения, [`docs/incidents/`](docs/incidents/) — что ломалось,
[`docs/research/`](docs/research/) — стандарты, на которые опираются решения.
