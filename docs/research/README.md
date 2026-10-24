# Исследования

Внешние исследования, на которые опираются ADR, README юнитов и алерты: сравнение
вариантов, первичные источники, вывод «что выбрали и почему». Здесь **не** описано
текущее состояние стенда — оно в README/RUNBOOK юнитов, в `docs/adr/` и в
`docs/status/`.

## Правила

- Тема — папка. Новое исследование кладётся в папку своей темы; если темы нет,
  создаётся папка.
- Имя файла самодостаточно: на него ссылаются из юнитов и ищут `grep`-ом, поэтому
  папку в имени не повторяем (`home-assistant/device-audit.md`, а не
  `home-assistant/home-assistant-device-audit.md`).
- Первая строка после заголовка — `Дата проверки: YYYY-MM-DD`. Дата — это когда
  факты сверялись с первоисточниками, а не когда файл создан.
- Если документ перестал быть правдой, в шапку добавляется
  `> **Устарело:**` с указанием, чем руководствоваться вместо него. Такой документ
  остаётся как история решения, но не как руководство.

## Темы

| Тема | О чём |
| --- | --- |
| [`agents/`](agents/) | доступ AI-агентов к серверу, кластеру и сессиям с телефона |
| [`artifacts/`](artifacts/) | кэширование внешних пакетов и бинарников |
| [`communication/`](communication/) | почта, видеозвонки, Nextcloud Talk |
| [`data/`](data/) | базы и хранилища данных приложений |
| [`git/`](git/) | платформа хостинга Git |
| [`home-assistant/`](home-assistant/) | устройства умного дома и их подключение |
| [`identity/`](identity/) | провайдеры идентичности, SSO по сервисам, жизненный цикл учёток |
| [`k8s/`](k8s/) | дистрибутивы, сеть, хранилище, GitOps, инструменты Kubernetes |
| [`media/`](media/) | медиасерверы |
| [`network/`](network/) | DNS и сетевая инфраструктура |
| [`observability/`](observability/) | метрики, логи, трейсы, аптайм-мониторинг |
| [`secrets/`](secrets/) | провайдеры секретов, раскладка в Vault, инвентаризация |
| [`security/`](security/) | аудит и гигиена репозитория |
| [`storage/`](storage/) | протоколы разделяемого и сетевого хранилища |

## Документы

### agents

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`agent-remote-server-access.md`](agents/agent-remote-server-access.md) | как агент с ноутбука получает доступ к серверу: SSH + ssh-agent, Tailscale | 2026-08-17 |
| [`agent-mobile-access.md`](agents/agent-mobile-access.md) | доступ к сессиям агентов и локальным LLM с телефона: T3 Code, `opencode web/serve` | 2026-08-16 |

### artifacts

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`artifact-caching.md`](artifacts/artifact-caching.md) | кэш внешних пакетов: OCI, npm, apt, Go; сравнение реестров и mirror-решений | 2026-09-21 |
| [`http-binary-cache.md`](artifacts/http-binary-cache.md) | generic HTTP-кэш для бинарников и релизов: ATS, nginx, Varnish, Squid | 2026-09-23 |

### communication

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`email-servers.md`](communication/email-servers.md) | self-hosted почтовые серверы, клиенты и инструменты | 2026-08-19 |
| [`video-calling.md`](communication/video-calling.md) | решения для видеозвонков: self-hosted и коммерческие | 2026-08-17 |
| [`nextcloud-talk-media.md`](communication/nextcloud-talk-media.md) | медиа-топология Nextcloud Talk (HPB/SFU) и высокая загрузка на macOS | 2026-08-18 |

### data

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`valkey-vs-redis.md`](data/valkey-vs-redis.md) | Valkey против Redis после смены лицензии | 2026-08-23 |

### git

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`forgejo-vs-gitlab.md`](git/forgejo-vs-gitlab.md) | Forgejo против GitLab CE для homelab | 2026-08-17 |
| [`gitea-vs-forgejo.md`](git/gitea-vs-forgejo.md) | Gitea против Forgejo: форк, управление, направление развития | 2026-08-20 |

### home-assistant

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`appliance-integration-paths-home-assistant.md`](home-assistant/appliance-integration-paths-home-assistant.md) | стиральная/сушильная машины и посудомойка: пути интеграции | 2026-08-21 |
| [`babai-curtain-cmb5-home-assistant.md`](home-assistant/babai-curtain-cmb5-home-assistant.md) | шторы Babai CMB5 (`babai.curtain.cmb5`) | 2026-08-21 |
| [`home-assistant-device-audit.md`](home-assistant/home-assistant-device-audit.md) | аудит умных устройств дома и что из них подключается | 2026-08-21 |
| [`intercom-camera-home-assistant.md`](home-assistant/intercom-camera-home-assistant.md) | камера домофона Novihome COMFY 10 | 2026-08-21 |

### identity

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`identity-providers.md`](identity/identity-providers.md) | обзор и выбор IdP (ZITADEL) для сервисов homelab | 2026-08-16 |
| [`idp-comparison-matrix.md`](identity/idp-comparison-matrix.md) | компактные таблицы сравнения IdP по всем параметрам | 2026-08-18 |
| [`per-service-auth-strategies.md`](identity/per-service-auth-strategies.md) | матрица OIDC/SSO-поддержки в конкретных сервисах | 2026-08-18 |
| [`identity-lifecycle.md`](identity/identity-lifecycle.md) | единый пользователь: SCIM, JML, back-channel logout, токены | 2026-08-18 |
| [`zitadel-vault-infisical.md`](identity/zitadel-vault-infisical.md) | ZITADEL как OIDC-провайдер для Vault и Infisical | — |

### k8s

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`argo-cd-vs-flux-cd.md`](k8s/argo-cd-vs-flux-cd.md) | Argo CD против Flux CD: модель, ресурсы, эксплуатация | 2026-08-24 |
| [`cni-solutions.md`](k8s/cni-solutions.md) | CNI: спецификация и выбор для k0s | 2026-09-12 |
| [`gitops-repo-structure.md`](k8s/gitops-repo-structure.md) | канон структуры GitOps-репозитория и раскладка этого homelab | 2026-09-18 |
| [`ingress-controllers-and-gateway-api.md`](k8s/ingress-controllers-and-gateway-api.md) | Ingress-контроллеры и Gateway API | 2026-10-01 |
| [`k0s-kubernetes-distribution.md`](k8s/k0s-kubernetes-distribution.md) | k0s: устройство, компоненты, возможности | — |
| [`k0s-setup-guide-vanilla.md`](k8s/k0s-setup-guide-vanilla.md) | установка k0s на Fedora Server близко к ванильному Kubernetes | 2026-08-27 |
| [`k3s-vs-k0s-detailed-comparison.md`](k8s/k3s-vs-k0s-detailed-comparison.md) | K3s против k0s: детальное сравнение | 2026-08-27 |
| [`kubernetes-distributions-comparison.md`](k8s/kubernetes-distributions-comparison.md) | дистрибутивы Kubernetes: полное сравнение | 2026-08-25 |
| [`kubernetes-metrics-stack.md`](k8s/kubernetes-metrics-stack.md) | метрики в Kubernetes: операторы, CRD, готовые дашборды | 2026-09-18 |
| [`linting-tools-comparison.md`](k8s/linting-tools-comparison.md) | линтеры и валидаторы манифестов | 2026-08-31 |
| [`manifest-field-ordering.md`](k8s/manifest-field-ordering.md) | порядок полей в манифестах, форматтеры, CRD | 2026-09-25 |
| [`remote-access-metallb-solutions.md`](k8s/remote-access-metallb-solutions.md) | удалённый доступ к сервисам при MetalLB L2 | — |
| [`storage-classes-and-csi-provisioners.md`](k8s/storage-classes-and-csi-provisioners.md) | StorageClass и CSI-провижионеры | — |
| [`yandex-cloud-kubernetes.md`](k8s/yandex-cloud-kubernetes.md) | Kubernetes в Yandex Cloud: managed-сервис, StorageClass, CRD | — |

### media

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`jellyfin.md`](media/jellyfin.md) | Jellyfin: образ, теги, запуск | 2026-08-10 |

### network

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`pihole-vs-technitium.md`](network/pihole-vs-technitium.md) | DNS-сервер: Pi-hole против Technitium, включая DoH и API | 2026-08-20 |

### observability

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`observability-standards.md`](observability/observability-standards.md) | подходы, стандарты и протоколы телеметрии | 2026-09-14 |
| [`monitoring-stacks-overview.md`](observability/monitoring-stacks-overview.md) | анатомия мониторинга, сравнение стеков, план внедрения | 2026-08-21 |
| [`observability-pitfalls.md`](observability/observability-pitfalls.md) | реальные грабли при настройке стека | — |
| [`log-output-formats.md`](observability/log-output-formats.md) | какой контейнер отдаёт JSON, logfmt или текст | 2026-09-28 |
| [`uptime-kuma-declarative-config.md`](observability/uptime-kuma-declarative-config.md) | декларативная конфигурация Uptime Kuma 2.x | 2026-08-14 |
| [`uptime-monitoring-alternatives.md`](observability/uptime-monitoring-alternatives.md) | декларативная альтернатива Uptime Kuma (Gatus) | 2026-08-14 |

### secrets

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`secret-management-providers.md`](secrets/secret-management-providers.md) | сравнение провайдеров управления секретами | 2026-08-19 |
| [`vault-secret-path-layout.md`](secrets/vault-secret-path-layout.md) | иерархия путей и структура ACL в Vault | 2026-09-26 |
| [`secrets-consumers-inventory.md`](secrets/secrets-consumers-inventory.md) | инвентаризация: кто какие секреты читает | 2026-09-26 |
| [`config-templating.md`](secrets/config-templating.md) | шаблонизация конфигов с секретами — **устарело**, см. шапку документа | 2026-08-22 |

### security

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`security-audit-standards.md`](security/security-audit-standards.md) | аудит перед публикацией: стандарты, инструменты, раскрытие секретов | 2026-09-20 |

### storage

| Документ | О чём | Проверено |
| --- | --- | --- |
| [`overview.md`](storage/overview.md) | протоколы разделяемого хранилища: обзор и сводка выбора | 2026-10-13 |
| [`block-and-cluster.md`](storage/block-and-cluster.md) | блочные протоколы и кластерные/распределённые ФС | 2026-10-13 |
| [`file-level-protocols.md`](storage/file-level-protocols.md) | NFS, SMB, FTP/SFTP, rsync, 9P | 2026-10-13 |
| [`object-storage-and-cloud-drives.md`](storage/object-storage-and-cloud-drives.md) | объектные протоколы и «облачные диски» | 2026-10-13 |
| [`google-drive-alternatives.md`](storage/google-drive-alternatives.md) | self-hosted альтернативы Google Drive | — |
| [`laptop-disk-as-storage.md`](storage/laptop-disk-as-storage.md) | диск ноутбука как сетевая ФС или блочное устройство | 2026-08-16 |
