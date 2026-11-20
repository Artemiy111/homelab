# Матрица поддержки OIDC в сервисах homelab

Дата: 2026-11-20.

Обновление для задачи объединения исследований: первоисточниками обновлённых
данных послужили манифесты юнитов (`apps/casa/`, `platform/casa/`),
`clusters/casa/argocd/apps/*.yaml`, `infra/casa/terraform/zitadel/`,
`infra/casa/terraform/vault/`, серии запросов по документации upstream
(GitHub, vendor-док, vendor-блоги) — за исключением таблиц сравнения провайдеров
(§0 в [idp-comparison-matrix.md](idp-comparison-matrix.md), версия 2026-08-18).

Правила использования:

- **Upstream SSO** — то, что предоставляет сам сервис (нативно или через
  плагин/сторонний плагин). Сейчас в стенде может быть не настроено.
- **«Сейчас в кластере»** — фактическое состояние по репозиторию.
- Подробные особенности — в шапке юнита: [README.md](apps/casa/README.md)
  (units) и в [начальной матрице](idp-comparison-matrix.md).
- Стенд по списку сервисов не делится: «не используется» и «не развёрнут» —
  разные вещи, записаны отдельно.

Порядок подключения нового приложения к текущей схеме (quickstart) — на
следующей странице, сразу после таблиц. Подходит и для «актуализации»: если
новый OIDC-клиент в ZITADEL написан, по порядку определяем, что должно
измениться в приложении.

---

## Последовательность подключения нового приложения (quickstart)

1. **Решить путь.** Native OIDC → ZITADEL (уже есть OIDC-приложение: Forgejo,
   Immich, GlitchTip, MAS, Home Assistant — система настроена). ForwardAuth →
   OAuth2 Proxy перед приложением (если нет native OIDC). Иначе — локальный
   вход.
2. **Завести OIDC-приложение в ZITADEL** (за 5-минутную инструкцию:
   redirect URIs, `id_token_userinfo_assertion` только при нужде,
   деплой через [Terraform](infra/casa/terraform/zitadel/)). Проверить
   discovery, JWKS.
3. **Собственно конфигурацию приложения** (env OAuth2 в манифестах,
   настройка callback, role claim, локальные аккаунты).
4. **JIT + admin group**: кто назначает админа в приложении — вручную
   после каждого нового входа, через группу в ZITADEL (`admin` — паттерн
   Forgejo), если позволяет чарт.
5. **BCL/жизненный цикл** — окна уязвимости — [§4 матрицы](idp-comparison-matrix.md).
6. **Декларативность**: права приложения, настройки секретов и сертификатов
   — в GitOps. Пароли — через Vault, никогда в коде.

---

## A. Настроенный OIDC — вход работает через ZITADEL прямо сейчас

| Сервис | Поддержка (всегда проверяется upstream) | Сейчас в кластере | Примечания |
|---|:---:|:---:|---|
| **Forgejo** (16-rootless) | ✅ | ✅ | Локальная форма входа — как страховка; все клиенты — через ZITADEL. Новые учётки не создаются из колбэка (auto-registration выключен): отправляет на `/user/link_account`, зарегистрировать локальный аккаунт снова — через [forgejo/README](apps/casa/forgejo/README.md). |
| **Immich** | ✅ | ✅ | OIDC-секция в манифестах: issuer, redirect, web+mobile, backchannel logout (`api/oauth/backchannel-logout`). Роль `admin` через claim `role` (`roleClaim`) + Actions. |
| **MAS (Matrix Auth Service)** | ✅ | ✅ | Все клиенты входят из ZITADEL; паролей нет; вход через `urn:mas:admin` — админ выставляется вручную. |
| **Element (Synapse)** | ✅ (через MAS) | ✅ | Native OIDC — Synapse → MAS → ZITADEL. |
| **GlitchTip** | ✅ | ✅ | Per-org SSO в v6+ нативно. |
| **Home Assistant** | ✅ (HACS `hass-oidc-auth`) | ✅ | Вход из ZITADEL; пароль отключён. |
| **Zot** | ✅ | ⚠️ не сейчас | Приложение создано в Terraform; реестр анонимный (`anonymous read only`), причина — [zot docs](https://zotregistry.dev/v2.1.21/articles/authn-authz/). |
| **Beszel** | ✅ | ⚠️ не сейчас | Приложение создано в Terraform, но стенд выведен из эксплуатации (`replicas: 0`). |

---

## B. Поддержка есть, не настроено

| Сервис | Как настраивается по документации upstream | Сейчас в кластере | Комментарии |
|---|---|---|---|
| **Nextcloud** | `user_oidc` 8.10.1 (`occ user_oidc:provider add`): auto-provisioning + group provisioning; WebDAV/desktop/mobile OIDC-стабильность. | Нет выбора конфигурации OIDC в стенде | Вход — локальный (`config.php` + `occ`), доступ WebDAV тоже локальный. |
| **Open WebUI** | Native OIDC/OAuth + LDAP: конфиг через env в деплойменте (`OAUTH_*`, `OPENID_*`). | Не настроено | Первый пользователь — админ. |
| **Paperless-ngx** | Native OIDC via allauth/SPSSO (`PAPERLESS_APPS`), remote-user header, OIDC token auth method. | Не настроено | |
| **Linkwarden** | Native OIDC via NextAuth. Включить — требует кастомную сборку образа (`NEXT_PUBLIC_*` запечатоны в деплойменте) | Не настроено | Для включения — отдельная задача на сборку. |
| **Sure** | Native OIDC (`OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_ISSUER`, `OIDC_REDIRECT_URI`). | Не настроено | |
| **Stirling PDF** | OAuth2/OIDC SSO на всех планах (Google, GitHub; SAML/SCIM — Enterprise), конфиг `security.oauth2.*`. | Не настроено | |
| **RustFS** | OIDC/SSO доступен для console (`RUSTFS_IDENTITY_OPENID_*`). | Не настроено | Доступ S3 — SigV4 root-креденшления из Vault (`kv/rustfs/credentials`). |
| **Technitium DNS** | SSO с OIDC доступен (см. [technitium.com/dns](https://technitium.com/dns/)); выступление всё-таки по токенам. | Не настроено | |
| **Code-server** | Нет клиента для OIDC; безопасность — пароль. | Пароль | Дескриптор пароля в PV. |
| **Homepage** | Опциональный нативный вход (opt-in); по умолчанию — открытый dashboard. | Без входа | Статический dashboard. |
| **OpenList** | Native OIDC (запросы issues на golang/oidc в коде). | Маршрут за forward-auth (развёрнуто за proxy). |
| **SAMBA** | SMB/SMB2/3. Не SSO. | Не настроено | AD-членство возможно по запросу, но не для стенда. |

---

## C. Собственный вход, SSO не у приложения (или без SSO)

| Сервис | Вход | Примечания |
|---|---|---|
| **Argo CD** | Локальный `admin` | OIDC-конфиг уже настраивается руками в `platform/casa/argocd/values.yaml` (закомментирован, ожидает OIDC в кластере). |
| **Mailserver (Stalwart + Bulwark)** | Stalwart admin + JMAP login | Админ — пароль из Vault (`kv/mailserver/secret`). |
| **GitLab CE (тестовый стенд)** | Локальный вход | Отдельный тестовый стенд, в основном для оценки. |
| **Navidrome** | Externalized auth (ReverseProxy user header) + OpenSubsonic-клиенты | |
| **Jellyfin** | Third-party SSO плагин (статус-форки) | 9p4/jellyfin-plugin-sso архивирован; в последних днях хорошо поддерживаются форки (K0lin, ZL154/JellyfinSecurity). |
| **Uptime Kuma** | Свой локальный вход | Требование OIDC открыто; PR с OIDC SSO не влит. |
| **Athens** | Локальная форма входа; OIDC — нет. | Локальный доступ, часто в LAN. |
| **Verdaccio** | Htpasswd (`max_users: -1` — регистрация отключена). | Поддержка — community-плагин (`verdaccio-openid`), не подключён. |
| **3x-ui** | Свой пароль | LAN-only намеренно; снаружи доступ только по открытым портам (`Xray 8443`). |
| **Pi-hole** | Не в кластере (в пользу Technitium; OIDC возможен) | — |
| **postgres** | Локальный вход | Playground-стенд, базы в основном. |
| **Grafana** | Локальный admin + oauth2-proxy перед ним | Зависимый, OIDC нативно — отдельная таблица D. |

---

## D. Приложения через OAuth2 Proxy (forwardAuth)

| Сервис | Параметры входа сейчас | Примечания |
|---|---|---|
| **Structurizr** | forwardAuth на внешнем хосте `oauth.example.com` (подключен к OIDC-клиенту) | Нет собственной аутентификации. |
| **Grafana** | oauth2-proxy перед ним; локальный admin | Native OIDC нативно, но клиент не настроен. |
| **Filestash** | forwardAuth; admin-вход отдельный | OIDC в OSS — только htpasswd/LDAP; ключевая причина закрытия: реестр `ntfs1` шара (см. README). |
| **Element Admin** | forwardAuth | Статический SPA (хранит настройки MAS). |
| **Trivy Operator Dashboard** | forwardAuth | Дашборд над тривией-операторами; защита forward-auth |
| **VictoriaMetrics** | forwardAuth (веб-интерфейс открыт). | Без входа сейчас; данные на VM живут в Victoria; перенос в JWT/Influx решается после настройки OIDC-клиента. |
| **Longhorn** | forwardAuth | API-открытый. |
| **Traefik Dashboard** | forwardAuth | API-открытый. |

---

## E. Без входа (статика, публичные dashboard, NATS)

- **Lute** — свой app, stateless.
- **Mermaid Live Editor** — статика.
- **Petri Nets** — собственный, нет входа, все данные в браузере (GitOps'd, см. README).
- **Talk HPB** — internal, внутренний API-token.
- **Vault (секреты)** — вход: токен `kubernetes` для pod'ов (VSO), человеческий — root-token (см. матрицу, §4).

---

## Факт-чек: источники по первичным фактам (2026-11-20)

| Факт | Источник |
|---|---|
| ZITADEL OIDC-клиенты | [applications.tf](infra/casa/terraform/zitadel/applications.tf) |
| Список за прокси | [oauth2-proxy.README](apps/casa/oauth2-proxy/README.md); маршруты: `apps/casa/*/manifests/route.yaml` |
| Forgejo SSO | [forgejo/README](apps/casa/forgejo/README.md) §«Вход через Zitadel» |
| Immich SSO | [immich/README](apps/casa/immich/README.md), [immich/RUNBOOK](apps/casa/immich/RUNBOOK.md) |
| MAS/Element SSO | [mas/README](apps/casa/mas/README.md) |
| GlitchTip SSO | [glitchtip/README](apps/casa/glitchtip/README.md) |
| HA SSO | [home-assistant/README](apps/casa/home-assistant/README.md) |
| Argo | [platform/casa/argocd/README.md](platform/casa/argocd/README.md) |
| Глобальные факты lifecycle/JML/BCL | [idp-comparison-matrix.md](idp-comparison-matrix.md) |

---

## Особенности по приложениям (вторичные таблицы)

### Forgejo

- Поля в [forgejo/RUNBOOK.md](apps/casa/forgejo/RUNBOOK.md).
- JIT-клиенты из Terraform; auto-registration off.
- Правило имени колбэка — из "Zitadel" (исторический комментарий в [applications.tf](infra/casa/terraform/zitadel/applications.tf)).

### Immich

- Native OIDC (мобильные callback совпадают с web).
- Backchannel logout (технически подключено на клиенте).

### MAS + Element

- Passwords disabled — единственный путь входа — из ZITADEL.
- `urn:mas:admin` — отдельный scope; admin по `can_request_admin`.
- Сокращённый путь: Element → MAS → ZITADEL (upstream OIDC), в кластере — как развернуто.

### GlitchTip

- Allauth/OAuth (provider_id `zitadel` в настройках); в Declarative provisioning через init-контейнер; admin — ручной.

### Home Assistant

- hass-oidc-auth контейнер-агент + zitadel client в кластере.

### Technitium DNS

- SSO с OIDC доступно для web-форм; доступ к админке — по паролю (см.
  шапку юнита; SSO через админку не подключен).

---

## Описание состояния: специфические имена

| Клиент в ZITADEL | Текущий статус | Причина |
|---|---|---|
| Oauth Proxy | ✅ подключён (ForwardAuth) | Structurizr, Grafana, Filestash, OpenList, Element Admin, Trivy Dashboard |
| Element | ⚠️ legacy | Synapse работает через MAS, не Element OIDC app. |
| Zot | ⚠️ есть клиент | anonymous read only. |
| Beszel | ⚠️ не развёрнут | — |

---

## Отсылка на другие документы

- Провайдеры и компаративные таблицы — [idp-comparison-matrix.md](idp-comparison-matrix.md).
- Жизненный цикл, SCIM, BCL, token lifetime — там же, §4 (общий для всех приложений).
- Краткие рекомендации по конфигурации, callback-и, admin groups — [README юнитов](apps/casa/README.md).
