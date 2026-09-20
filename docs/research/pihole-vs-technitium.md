# Pi-hole vs Technitium DNS Server

Дата исследования: 2026-08-20.

## Обзор

| | Pi-hole | Technitium DNS Server |
|---|---|---|
| **Назначение** | DNS-прокси для блокировки рекламы/трекеров | Полноценный DNS-сервер (authoritative + recursive + блокировка) |
| **Язык** | C + PHP + JavaScript | C# (.NET 10) |
| **Лицензия** | MIT | GPL v3 |
| **Репозиторий** | [github.com/pi-hole/pi-hole](https://github.com/pi-hole/pi-hole) (60.5k ⭐) | [github.com/TechnitiumSoftware/DnsServer](https://github.com/TechnitiumSoftware/DnsServer) (9.5k ⭐) |
| **Docker** | `pihole/pihole` ~130 MB | `technitium/dns-server` ~200 MB |
| **БД** | SQLite | SQLite |
| **Веб-интерфейс** | Dashboard (lighttpd) | Полноценная админ-панель (Kestrel) |
| **API** | Ограниченный (FTL API v5) | REST API (полный) |

---

## Полноценная сравнительная таблица

### 🌐 DNS

| Возможность | Pi-hole | Technitium |
|-------------|:-------:|:----------:|
| Рекурсивный DNS | ⚠️ Через add-on Unbound | ✅ Встроенный |
| Authoritative DNS | ❌ | ✅ Полное управление зонами |
| Primary / Secondary / Stub зоны | ❌ | ✅ |
| Conditional Forwarder zones | ❌ | ✅ |
| Catalog zones (RFC 9432) | ❌ | ✅ Автоматический provisioning |
| DNS-over-HTTPS (сервер) | ❌ Только через reverse proxy | ✅ Встроенный |
| DNS-over-TLS (сервер) | ❌ | ✅ Встроенный |
| DNS-over-QUIC (RFC 9250) | ❌ | ✅ Встроенный |
| DNS-over-HTTP/3 | ❌ | ✅ |
| DNSSEC | ⚠️ Через upstream/dnsmasq | ✅ Нативная валидация (RFC 8080 Ed25519/Ed448) |
| Zone Transfers (AXFR) | ❌ | ✅ Включая XFR-over-QUIC |
| Split-horizon DNS | ❌ | ✅ Split Horizon App |
| DNS Failover | ❌ | ✅ Conditional Forwarder с приоритетами |
| EDNS Client Subnet (ECS) | ❌ | ✅ |
| Кластеринг | ❌ | ✅ Multi-node кластер (v14.0+) |
| Prometheus метрики | ❌ | ✅ Lifetime counters (v15.0+) |
| QNAME minimization | ❌ | ✅ |
| DNS Rebinding Protection | ❌ | ✅ App |
| Авто PTR записи | ❌ | ✅ Auto PTR App |

### 🛡️ Блокировка

| Возможность | Pi-hole | Technitium |
|-------------|:-------:|:----------:|
| Блокировка рекламы/трекеров | ✅ Основная функция | ✅ Встроенная опция |
| Обновление списков | ✅ Gravity | ✅ Встроенный auto-update |
| Форматы списков | ⚠️ Только hosts-файлы | ✅ hosts + Adblock Plus + wildcard |
| Расширенная блокировка | ❌ | ✅ Advanced Blocking App (по группам, TTL) |
| Block Page | ❌ | ✅ Block Page App (SSL MiTM) |
| Per-device фильтрация | ✅ Группы | ✅ Группы + клиентские подсети |
| DNS Rewrite записи | ✅ Local DNS | ✅ Local zones + apps |
| Обнаружение блокировки от upstream | ❌ | ✅ Quad9 DNSSEC blocking |

### 🔐 Безопасность и аутентификация

| Возможность | Pi-hole | Technitium |
|-------------|:-------:|:----------:|
| Парольная аутентификация | ✅ | ✅ |
| 2FA (TOTP) | ✅ | ✅ |
| OpenID Connect (OIDC) SSO | ❌ | ✅ v15.0+ (апрель 2026) |
| JIT provisioning (автосоздание аккаунтов) | ❌ | ✅ Через OIDC claims |
| RBAC (маппинг roles → группы) | ❌ | ✅ OIDC `roles` claim |
| Application passwords (API) | ✅ | ✅ Bearer tokens |
| HTTPS | ⚠️ Через reverse proxy | ✅ Встроенный (self-signed / import cert) |
| Rate limiting | ✅ | ✅ Настраиваемый QPM |
| Brute force protection | ✅ | ✅ IPv4 + IPv6 |
| Non-root service | ❌ Запуск от root | ✅ v15.0+ non-root systemd |

### 📦 DHCP

| Возможность | Pi-hole | Technitium |
|-------------|:-------:|:----------:|
| DHCP-сервер | ✅ | ✅ |
| Статические лизы | ✅ | ✅ |
| Авто-регистрация в DNS | ✅ | ✅ Persistent DNS для reserved |

### ☸️ Kubernetes

| Возможность | Pi-hole | Technitium |
|-------------|:-------:|:----------:|
| Официальный Helm-чарт | ❌ | ❌ Community charts |
| Community Helm-чарт | ⚠️ ([k8s-at-home/pihole](https://github.com/k8s-at-home/charts)) | ⚠️ ([k8s-at-home/technitium](https://github.com/k8s-at-home/charts)) |
| Нативный random-builtin конфиг | ❌ Требует PVC для gravity.db | ✅ Конфиг в `/etc/dns` (backup/restore) |
| StatefulSet (PersistentVolume) | ✅ Нужен для gravity.db и lists | ✅ Нужен для SQLite + zone files |
| Headless Service (DNS) | ✅ `type: ClusterIP` | ✅ `type: ClusterIP` |
| DNS в ClusterIP (CoreDNS replacement) | ⚠️ Возможен, но не рекомендуется | ✅ Возможен как authoritative + recursive |
| Multi-replica (кластеринг) | ❌ Один экземпляр | ✅ Кластеринг через веб-панель |
| Prometheus ServiceMonitor | ❌ | ✅ `/metrics` endpoint |
| NetworkPolicy совместимость | ✅ | ✅ |
| Ingress (web UI) | ✅ Через Ingress-контроллер | ✅ Через Ingress-контроллер |
| DNS over NodePort/DaemonSet | ✅ Популярный паттерн | ✅ Популярный паттерн |
| ARM64 / multi-arch | ✅ | ✅ .NET multi-arch |
| Ресурсы (CPU/RAM) | 🪶 Минимальные (~30 MB RAM) | 📦 Средние (~150 MB RAM, .NET runtime) |

### 🛠️ Управление и мониторинг

| Возможность | Pi-hole | Technitium |
|-------------|:-------:|:----------:|
| Web Dashboard | ✅ Статистика запросов | ✅ Полноценный (запросы, зоны, apps) |
| REST API | ⚠️ Ограниченный (FTL API) | ✅ Полный (управление всем) |
| Логирование запросов | ✅ В SQLite | ✅ В SQLite + Apps для PostgreSQL/MySQL/MSSQL |
| Экспорт логов (CSV) | ❌ | ✅ |
| Графики / статистика | ✅ Базовая | ✅ Расширенная (по типам протоколов) |
| Уведомления | ✅ Telegram / email | ✅ Встроенные |
| Backup / Restore | ⚠️ Через gravity.list | ✅ Встроенный (zip export/import) |
| CLI управление | ✅ `pihole` CLI | ❌ Только через web/API |

---

## 🔑 Поддержка OpenID Connect

### Pi-hole: ❌ Нет нативной поддержки

Pi-hole использует собственную session-based аутентификацию:
- `POST /api/auth` с паролем → session ID (SID)
- Поддержка 2FA (TOTP)
- Application passwords для API

**OIDC не реализован и не запланирован** (по состоянию на август 2026).
Обсуждений на GitHub по OIDC/SSO нет.

**Обходные пути:**
1. **OAuth2 Proxy** перед Pi-hole — дополнительный барьер аутентификации перед собственным login
2. **Traefik forwardAuth** middleware — аналогичный подход

В обоих случаях внутренняя auth Pi-hole сохраняется. OIDC не заменяет пароль.

Источник: [Pi-hole API Auth](https://docs.pi-hole.net/api/auth/), `docs/research/oidc-support.md:35,65,552`

---

### Technitium: ✅ Нативная поддержка (v15.0+, апрель 2026)

Technitium DNS Server v15 добавил **нативный OpenID Connect (OIDC) SSO**.
Это полноценная интеграция — приложение выступает как OIDC Relying Party.

**Ключевые возможности:**
- SSO через любой совместимый OIDC Provider (ZITADEL, Keycloak, Authentik, Authelia, Okta)
- Маппинг OIDC claims `roles` → группы Technitium (DNS Admins, DNS Administrators и др.)
- JIT provisioning (автосоздание аккаунтов при первом входе)
- Отключение локальной аутентификации (OIDC-only вход)

**Callback URL:**

```text
https://<technitium-host>/sso/callback
```

**Scope:**

```text
openid email profile roles
```

**Настройка в Technitium:**
Settings → SSO → Enable OpenID Connect → ввести:
- Issuer URL (Discovery URL)
- Client ID / Client Secret
- Scopes: `openid email profile roles`

**Настройка в IdP (пример ZITADEL):**
- Создать приложение (OIDC / Web)
- Redirect URI: `https://<technitium-host>/sso/callback`
- Client ID / Secret → в Technitium
- Role mapping: `roles` claim → группы

**Интеграция с Authentik:**
Официальная документация: [Integrate with Technitium DNS](https://integrations.goauthentik.io/networking/technitium/)

**Интеграция с Authelia:**
Рабочий пример: [GitHub Discussion #1988](https://github.com/TechnitiumSoftware/DnsServer/discussions/1988)

Источники:
- [Technitium Blog: v15 Released](https://blog.technitium.com/2026/04/technitium-dns-server-v15-released.html)
- [CHANGELOG v15.0](https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md)
- [authentik Integration](https://integrations.goauthentik.io/networking/technitium/)
- [Authelia Guide](https://github.com/TechnitiumSoftware/DnsServer/discussions/1988)

---

## 🚀 Развёртывание

| Аспект | Pi-hole | Technitium |
|--------|:-------:|:----------:|
| Bare-metal / VM | `curl -sSL \| bash` | `curl -sSL \| bash` / Installer |
| Docker | `pihole/pihole` | `technitium/dns-server` |
| Kubernetes (Helm) | ⚠️ Community | ⚠️ Community |
| Конфигурация по умолчанию | ✅ Из коробки | ✅ Из коробки |
| Доп. компоненты | ⚠️ Unbound для рекурсии | ✅ Не требуются |
| Минимальные ресурсы | 🪶 Raspberry Pi Zero | 📦 .NET runtime |
| Обновление | `pihole -up` | Installer script / Docker pull |

---

## 📋 Когда выбирать Pi-hole

- Нужна простая блокировка рекламы/трекеров в сети
- Минимальные ресурсы (Raspberry Pi Zero)
- Максимальное сообщество (60k+ звёзд, множество гайдов)
- Нетребовательность к DNS-функционалу
- Kubernetes:只想 leichtgewichtiges DNS-Blocking

## 📋 Когда выбирать Technitium

- Нужен полноценный DNS-сервер (authoritative + recursive)
- Нужны zone transfers, кластеринг, Split-horizon
- Нужен нативный OIDC SSO для единого входа
- Нужны расширенные возможности блокировки (apps, custom logic)
- Нужен Prometheus мониторинг
- Kubernetes: multi-replica кластеринг, ServiceMonitor, как CoreDNS replacement
- Enterprise-подобная среда (несколько нод, TLS, DoQ)

---

## 📌 Рекомендация для homelab

Для текущего стека homelab с ZITADEL как IdP:

### ✅ Technitium — предпочтительный выбор

| # | Преимущество |
|---|-------------|
| 1 | Нативный OIDC SSO → единый вход через ZITADEL |
| 2 | JIT provisioning → аккаунты создаются автоматически |
| 3 | Маппинг roles → группы для RBAC |
| 4 | Кластеринг → высокая доступность |
| 5 | Встроенный DoH/DoT/DoQ → не нужен reverse proxy для шифрования |
| 6 | Полноценный authoritative DNS → собственные зоны (.example.com) |
| 7 | Kubernetes: multi-replica, Prometheus,替代 CoreDNS |

### ⚠️ Pi-hole — альтернатива, если

| # | Условие |
|---|---------|
| 1 | Приоритет — простота и минимальные ресурсы |
| 2 | OIDC не критичен (OAuth2 Proxy как заглушка) |
| 3 | DNS-функционал не нужен (только блокировка) |
| 4 | Kubernetes:只 один replica, нет кластеринга |

---

## 📎 Связанные документы

- [oidc-support.md](oidc-support.md) — матрица OIDC поддержки всех сервисов homelab
- [idp-comparison-matrix.md](idp-comparison-matrix.md) — сравнение IdP провайдеров
- [authentication-services.md](authentication-services.md) — стратегии аутентификации
