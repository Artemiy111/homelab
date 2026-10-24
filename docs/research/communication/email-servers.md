# Self-Hosted Email: серверы, клиенты и инструменты

> Источники: [selfh.st/apps/?tag=Email](https://selfh.st/apps/?tag=Email), официальные сайты проектов, GitHub-репозитории, документация.
> Исследовано: 2026-08-19

---

## 1. Почтовые серверы

### Mail-in-a-Box

| | |
|---|---|
| Сайт | https://mailinabox.email/ |
| GitHub | https://github.com/mail-in-a-box/mailinabox (~15.4k ⭐) |
| Язык | Bash-скрипты + Python |
| Лицензия | CC0 (public domain) |
| Docker | ❌ — только Ubuntu 22.04 |

Онкликовая установка на чистый Ubuntu. Включает Postfix (SMTP), Dovecot (IMAP), Roundcube (webmail), Nextcloud (Contacts/CalDAV), SpamAssassin, Postgrey, DNS-сервер (nsd4) с DNSSEC/DANE/MTA-STS, SPF/DKIM/DMARC автоматически, Let's Encrypt TLS, автоматические бэкапы.

**Плюсы:** Самая простая настройка. Всё включено из коробки. Проверено с 2013 года, большое сообщество.

**Минусы:** Нет Docker. Очень авторитарный — почти нулевая настройка. Нельзя менять компоненты после установки. Только односерверная конфигурация.

**Статус:** Активен. Последний релиз v76 (май 2026). Maintainer: Joshua Tauberer.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ❌ | Нет |
| **SCIM 2.0** | ❌ | Нет |
| **LDAP** | ❌ | Нет |
| **OAuth2** | ❌ | Нет |
| **SAML** | ❌ | Нет |
| **WebAuthn/Passkeys** | ❌ | Только TOTP для админки |
| **2FA** | ⚠️ | Только TOTP, только для панели администратора. Webmail без 2FA |
| **JMAP** | ❌ | Dovecot не поддерживает |
| **CalDAV/CardDAV** | ✅ | Через Nextcloud |
| **Sieve** | ✅ | Pigeonhole, через Roundcube |
| **SPF/DKIM/DMARC** | ✅ | Автоматически |
| **DANE/MTA-STS** | ✅ | Автоматически |
| **ARC** | ❌ | Нет |
| **Admin API** | ✅ | REST API (OpenAPI 3.0.3), Basic Auth + API ключи |
| **SSO для webmail** | ❌ | Roundcube с простой парольной авторизацией |

**Вывод:** Почтовой «прибор» намеренно избегает enterprise-протоколов аутентификации. Рассчитан на одиночного пользователя / малую команду, не на федерацию.

---

### Mailcow

| | |
|---|---|
| Сайт | https://mailcow.email/ |
| GitHub | https://github.com/mailcow/mailcow-dockerized (~13.3k ⭐) |
| Язык | Bash + PHP (веб-UI), Docker-образы |
| Лицензия | GPL-3.0 |
| Docker | ✅ |

Полный Docker-стек: Postfix + Dovecot + Rspamd + ClamAV + SOGo groupware (CalDAV, CardDAV, ActiveSync). Веб-панель администратора, DKIM/SPF/DMARC/ARC/DANE/MTA-STS, антиспуфинг, greylisting, Prometheus-метрики, принудительная 2FA.

**Плюсы:** Самый функциональный Docker-почтовый сервер. SOGo совместим с Outlook. Активно поддерживается компанией The Infrastructure Company GmbH. Большое сообщество. Профессиональная поддержка.

**Минусы:** Требовательный к ресурсам (SOGo + все контейнеры). Сложный путь обновления. PHP UI выглядит устаревшим.

**Статус:** Активен. Релизы каждые 1–2 месяца (последний 2026-07a). 7,661 коммит.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ✅ (потребитель) | Mailcow — OIDC-клиент (не провайдер). Поддерживает Keycloak (первого класса) и Generic-OIDC. Только для почтовых ящиков; админы используют SQL-аутентификацию |
| **SCIM 2.0** | ❌ | Открытый PR [#7148](https://github.com/mailcow/mailcow-dockerized/issues/7148). Синхронизация через Keycloak Admin API или LDAP |
| **LDAP** | ✅ | Нативный бэкенд аутентификации (с 2025-03). Не требует Keycloak |
| **OAuth2** | ⚠️ | Mailcow — OAuth2-провайдер для внешних приложений (Nextcloud, Authentik и т.д.), но НЕ для аутентификации почтовых протоколов |
| **SAML** | ⚠️ | Частично сломан в свежих версиях (только SOGo, [#7238](https://github.com/mailcow/mailcow-dockerized/issues/7238)) |
| **WebAuthn/Passkeys** | ✅ | WebAuthn + Yubi OTP + TOTP — все три. WebAuthn-вход для админов/доменных админов; WebAuthn как 2FA — для всех |
| **2FA** | ✅ | TOTP, WebAuthn/FIDO2, Yubi OTP |
| **Протоколы** | ✅ | IMAP, POP3, SMTP, ManageSieve, CalDAV, CardDAV, ActiveSync |
| **JMAP** | ❌ | Dovecot не планирует |
| **Sieve** | ✅ | ManageSieve |
| **SPF/DKIM/DMARC** | ✅ | Через Postfix TLS-Pol + Rspamd |
| **ARC** | ✅ | |
| **DANE/MTA-STS** | ✅ | MTA-STS с 2025-09 |
| **SOGo SSO** | ⚠️ | Mailcow НЕ использует нативный OIDC SOGo. Аутентификация через Mailcow UI → proxy-auth → SOGo без повторного входа |
| **Внешние IdP** | ✅ | Keycloak (нативная интеграция), ZITADEL/Authelia/Authentik (через Generic-OIDC). Только один IdP одновременно |
| **Admin API** | ✅ | Полный REST API |

#### Детали OIDC-интеграции Mailcow

```
Пользователь → Mailcow UI → OIDC-провайдер (Keycloak/Generic-OIDC)
                                    ↓
                              Mailcow ← id_token
                                    ↓
                         Dovecot ← proxy_auth (master user)
```

- Почтовые клиенты (Thunderbird и т.д.) требуют **app passwords** при OIDC-аутентификации (кроме Keycloak с Mailpassword Flow)
- Админы и доменные админы НЕ могут использовать OIDC — только SQL
- SOGo открывается через proxy auth без повторного входа

---

### Stalwart

| | |
|---|---|
| Сайт | https://stalw.art/ |
| GitHub | https://github.com/stalwartlabs/stalwart (~14.2k ⭐) |
| Язык | Rust |
| Лицензия | AGPL-3.0 (Community) / SELv2 (Enterprise) |
| Docker | ✅ |

Всё-в-одном: SMTP + IMAP + POP3 + JMAP + CalDAV + CardDAV + WebDAV. Встроенный антиспам (статистический + LLM). Шифрование при хранении (S/MIME, OpenPGP). Гибкая система хранения: RocksDB, FoundationDB, PostgreSQL, MySQL, SQLite, S3, Azure Blob, Redis. Полнотекстовый поиск на 17 языках. LDAP, OIDC, SQL-аутентификация с 2FA. Кластеризация через Zenoh/Kafka/Redis/NATS. Независимый аудит безопасности.

**Плюсы:** Самая современная архитектура — один Rust-бинарник. Заменяет 5+ серверов. JMAP (современный протокол). Отличная кластеризация. Финансируется NLnet/EU.

**Минусы:** Ещё pre-1.0. Enterprise-функции требуют лицензии. AGPL отпугивает коммерческих пользователей. Меньше сообщество, чем у Mailcow.

**Статус:** Активен. 1,698 коммитов. Stalwart Labs LLC. Финансируется NLnet/EU.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ✅✅ | **И провайдер, и потребитель.** Stalwart может выступать OIDC-провайдером (выдаёт ID-токены) и аутентифицировать пользователей через внешний OIDC-провайдер (Keycloak, Authentik и т.д.) |
| **SCIM 2.0** | ❌ | Нет. Управление пользователями через UI, CLI или API |
| **LDAP** | ✅ | Нативный LDAP-бэкенд аутентификации |
| **OAuth2** | ✅ | Полный OAuth 2.0 провайдер: Authorization Code, Device Authorization (RFC 8628), динамическая регистрация клиентов |
| **SAML** | ❌ | Нет. Использует OAuth2/OIDC |
| **WebAuthn/Passkeys** | ❌ | Нет. Только TOTP 2FA |
| **2FA** | ⚠️ | Только TOTP |
| **JMAP** | ✅✅ | Полная поддержка: JMAP Mail (RFC 8621), JMAP Sieve, JMAP Calendars, JMAP Contacts (RFC 9610), JMAP File Storage, JMAP Sharing (RFC 9670), JMAP WebSocket (RFC 8887), JMAP Blob (RFC 9404), JMAP Quotas (RFC 9425), JMAP Push |
| **CalDAV** | ✅ | RFC 4791 + CalDAV Scheduling (RFC 6638) |
| **CardDAV** | ✅ | RFC 6352 |
| **WebDAV** | ✅ | RFC 4918 + WebDAV ACL (RFC 3744) |
| **Sieve** | ✅✅ | Все зарегистрированные расширения Sieve. ManageSieve (RFC 5804). JMAP для Sieve. LLM-интеграция в Sieve-скрипты |
| **Шифрование на диске** | ✅✅ | S/MIME и OpenPGP. Шифрование на уровне почтового ящика. Self-service портал управления ключами |
| **SPF/DKIM/DMARC** | ✅ | Полная поддержка, включая авто-ротацию ключей DKIM |
| **ARC** | ✅ | RFC 8617 |
| **DANE** | ✅ | RFC 6698 |
| **MTA-STS** | ✅ | RFC 8461 |
| **TLS-RPT** | ✅ | RFC 8460 |
| **Хранение данных** | ✅✅ | RocksDB, FoundationDB, PostgreSQL, MySQL, SQLite (данные); PostgreSQL, MySQL, SQLite, S3, Azure Blob, FS (blobs); встроенный, Meilisearch, ElasticSearch (поиск); Redis (кэш) |
| **Кластеризация** | ✅✅ | P2P (Zenoh) или координируемая (Kafka, NATS, Redis). Любой узел обслуживает любой протокол. HA, балансировка нагрузки |
| **Admin API** | ✅ | CLI + веб-API |

**Вывод:** Стандарт de facto для аутентификации и авторизации в self-hosted почте. Единственный сервер, который является одновременно OIDC-провайдером И OIDC-потребителем. JMAP — самый современный почтовый протокол.

---

### Mailu

| | |
|---|---|
| Сайт | https://mailu.io/ |
| GitHub | https://github.com/Mailu/Mailu (~7.5k ⭐) |
| Язык | Python (админка/веб), Docker-образы |
| Лицензия | MIT |
| Docker | ✅ |

Docker Compose развёртывание. IMAP, SMTP, Submission. Несколько вариантов webmail (Roundcube, SOGo и т.д.). Алиасы, доменные алиасы, кастомная маршрутизация. Полнотекстовый поиск вложений. Админ-веб-UI с делегированием по доменам. Принудительный TLS, DANE, MTA-STS, Let's Encrypt. ClamAV, Rspamd или SpamAssassin. Поддержка Kubernetes. PostgreSQL, MySQL, SQLite.

**Плюсы:** Настоящий Docker-нативный. Гибкость выбора компонентов. Хороший API админки.

**Минусы:** Более сложная начальная настройка. Документация отстаёт от кода. Требовательный к ресурсам.

**Статус:** Активен. Последний релиз 2024.06. 5,167 коммитов.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ❌ | Нет нативной поддержки. PR #2574 (нативный OIDC) был отклонён. Возможно через внешний прокси (Authentik, Keycloak) |
| **SCIM 2.0** | ❌ | Issue #3708 в обсуждении. Нет реализации |
| **LDAP** | ❌ | Нет нативного бэкенда. Старый PR #715 не был смержен |
| **OAuth2** | ❌ | Только косвенно, через внешний прокси |
| **SAML** | ❌ | Только через внешний прокси |
| **WebAuthn/Passkeys** | ❌ | Нет нативной 2FA. Код есть у мейнтейнера, но не смержен |
| **2FA** | ❌ | Нет нативной поддержки (TOTP PR #4010 был закрыт) |
| **Протоколы** | ✅ | IMAP, POP3, SMTP, CalDAV (через Radicale), CardDAV, WebDAV |
| **JMAP** | ❌ | Dovecot 2.3 не поддерживает |
| **Sieve** | ✅ | ManageSieve. Плагин в Roundcube включён по умолчанию |
| **SPF/DKIM/DMARC** | ✅ | Через Rspamd |
| **MTA-STS** | ✅ | С версии 1.9 |
| **DANE** | ✅ | С версии 1.9 |
| **ARC** | ⚠️ | Вероятно, через Rspamd |
| **Admin API** | ✅ | REST API с Swagger UI, токенная аутентификация |
| **Внешние IdП** | ⚠️ | Только через header authentication (`PROXY_AUTH_*`) |
| **SSO** | ⚠️ | Через oauth2-proxy/Authentik/Keycloak перед Mailu |

**Вывод:** Прочный почтовый сервер, но отстаёт в modern identity/SSO. Для OIDC/LDAP/SAML required внешний прокси.

---

### Postal

| | |
|---|---|
| Сайт | https://postalserver.io/ |
| GitHub | https://github.com/postalserver/postal (~16.7k ⭐) |
| Язык | Ruby (Rails) |
| Лицензия | MIT |
| Docker | ✅ |

Транзакционная почтовая платформа (self-hosted SendGrid/Mailgun/Postmark). Полный SMTP-сервер для отправки И приёма. Веб-UI для управления организациями, серверами, учётными записями. Отслеживание доставки, статистика, клики/открытия. Webhooks, API, управление пулами IP. DKIM, SPF, DMARC. Интеграция с Rspamd.

**Плюсы:** Заточен под транзакционную/прикладную почту. Отличный API и webhooks. Самый популярный на GitHub.

**Минусы:** **НЕ почтовый сервер для персонального использования** — нет webmail, нет IMAP для чтения. Для машинно-машинной доставки. Требует MySQL + RabbitMQ + Redis.

**Статус:** Активен. 657 коммитов. Maintained by Krystal.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ✅ | Полная поддержка через gem `omniauth_openid_connect`. Любые OIDC-провайдеры (Google, Keycloak и т.д.). Можно отключить локальную аутентификацию полностью |
| **SCIM 2.0** | ❌ | Нет |
| **LDAP** | ❌ | Нет. Нет LDAP-гемов в зависимостях |
| **OAuth2** | ❌ | Только как часть OIDC-флоу. Нет standalone OAuth2-провайдера |
| **SAML** | ❌ | Нет |
| **WebAuthn/Passkeys** | ❌ | Нет |
| **2FA** | ❌ | Нет |
| **DKIM** | ✅ | Генерация ключей, подпись |
| **SPF** | ✅ | DNS-конфигурация |
| **DMARC** | ⚠️ | Только на стороне DNS. Postal не генерирует и не проверяет DMARC |
| **API** | ⚠️ | v1 API только для отправки сообщений. Полноценного admin API нет (планируется v2) |
| **Webhooks** | ✅ | MessageSent, MessageDelayed, MessageFailed, MessageBounced, LinkClicked, Opened, DomainDNSError |
| **Модель данных** | | Organization → Server → Domain. Пользователи привязаны к организациям |

**Вывод:** Отличный OIDC для входа, но это не почтовый сервер для людей.

---

### Mox

| | |
|---|---|
| Сайт | https://www.xmox.nl |
| GitHub | https://github.com/mjl-/mox (~5.8k ⭐) |
| Язык | Go |
| Лицензия | MIT |
| Docker | ✅ (не рекомендуется автором) |

Однобинарниковый почтовый сервер. SMTP + IMAP4 + Webmail. SPF/DKIM/DMARC + DMARC aggregate reports. Reputation tracking + байесовская фильтрация спама (на пользователя). Автоматический TLS через ACME. DANE, MTA-STS, TLSRPT. Веб-админка + webmail. Prometheus-метрики, структурированные логи. Международная почта (EAI). Один конфиг-файл, минимальное обслуживание.

**Плюсы:** Экстремально низкое обслуживание. Отличное качество кода. Memory-safe Go. MIT. Финансируется NLnet/EU.

**Минусы:** Нет POP3, нет CalDAV/CardDAV/WebDAV, нет JMAP (в roadmap). Маленькое сообщество. Нет OAuth2, Sieve, ARC.

**Статус:** Активен. 1,077 коммитов. Solo-разработчик с EU-финансированием.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ❌ | Нет и не в roadmap |
| **SCIM 2.0** | ❌ | Нет. Управление через CLI/web-UI |
| **LDAP** | ❌ | Нет и не в roadmap |
| **OAuth2** | ⏳ | В roadmap: «OAUTH2 support, for single sign on» |
| **SAML** | ❌ | Нет |
| **WebAuthn/Passkeys** | ❌ | Нет. Поддерживается TLS certificate auth (`tlspubkeyadd`) как второй фактор |
| **2FA** | ❌ | Нет TOTP/WebAuthn. Есть TLS-сертификаты |
| **Протоколы** | ✅ | SMTP + IMAP4rev2 (RFC 9051) с расширениями: CONDSTORE, QRESYNC, IDLE, NAMESPACE, MULTIAPPEND, UIDPLUS, MOVE, METADATA, NOTIFY и др. |
| **JMAP** | ⏳ | В roadmap |
| **CalDAV/CardDAV** | ⏳ | В roadmap |
| **Sieve** | ⏳ | В roadmap. Сейчас — Rulesets в конфиге аккаунта |
| **SPF/DKIM/DMARC** | ✅✅ | Полная поддержка. DKIM — RSA и ed25519 |
| **ARC** | ⏳ | В roadmap |
| **MTA-STS** | ✅ | Полная поддержка (RFC 8461) |
| **DANE** | ✅ | Полная поддержка (RFC 7672) |
| **TLS-RPT** | ✅ | RFC 8460 |
| **Admin API** | ✅ | Web-админка + CLI ctl-сокет + WebAPI (HTTP/JSON) + Webhooks |

**Вывод:** Превосходная инженерия для базовой почты, но zero federated identity. Если нужен SSO — нет даже OAuth2. Фокус на «я работаю без внешних зависимостей».

---

### Dovel

| | |
|---|---|
| Сайт | https://dovel.email/ |
| Язык | Go |
| Лицензия | BSD-3-Clause |
| Docker | ✅ |

Минималистичный SMTP-сервер. Хуковая архитектура (скрипты обрабатывают входящую почту). DKIM для исходящих, PGP через WKD. Опциональный веб-интерфейс.

**Плюсы:** Экстремально лёгкий. Простейшая архитектура.

**Минусы:** Нет IMAP/POP3, нет webmail, нет антиспама, нет управления пользователями. Очень маленькое сообщество. Не подходит как основной почтовый сервер.

**Статус:** Низкая активность. v0.13.1.

#### Поддержка стандартов

| Стандарт | Поддержка |
|----------|-----------|
| **OIDC/LDAP/OAuth2/SAML/SCIM** | ❌ | Нет ничего из этого |
| **2FA** | ❌ | Нет |
| **Протоколы** | ⚠️ | Только SMTP (нет IMAP/POP3) |
| **DKIM** | ✅ | Для исходящих |
| **PGP** | ✅ | Через WKD |

---

### Nortix Mail

| | |
|---|---|
| GitHub | https://github.com/Zhoros/NortixMail (~712 ⭐) |
| Язык | Node.js + Svelte |
| Лицензия | MIT |
| Docker | ✅ |

Генератор одноразовых почтовых адресов. Получение и отправка с throwaway-адресов. Автопереадресация на реальный адрес.

**Плюсы:** Очень простая настройка. Заточен под приватность.

**Минусы:** НЕ почтовый сервер — только одноразовые адреса. Нет IMAP/POP3, нет DKIM/DMARC/SPF. 27 коммитов.

**Статус:** Очень низкий активность.

---

## 2. Сервисы переадресации / алиасов

### SimpleLogin

| | |
|---|---|
| Сайт | https://simplelogin.io/ |
| GitHub | https://github.com/simple-login/app (~6.9k ⭐) |
| Язык | Python (Flask) |
| Лицензия | AGPL-3.0 |
| Docker | ✅ |

Алиасы с переадресацией. Отправка/ответ с алиасов. Кастомные домены с catch-all. PGP-шифрование. Расширения Chrome/Firefox/Safari. Приложения iOS/Android (также F-Droid). Создание алиасов на лету через поддомены. TOTP + WebAuthn 2FA. OAuth «Sign in with SimpleLogin» как identity provider.

**Плюсы:** Самый зрелый сервис алиасов. Приобретён Proton AG. Уникальная фича — OAuth-провайдер.

**Минусы:** Self-hosting требует Postfix + PostgreSQL + Docker. Принадлежность Proton AG может смущать.

**Статус:** Активен. 5,341 коммит. Поддерживается Proton AG.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ✅ (провайдер) | SimpleLogin может быть OAuth/OIDC-провайдером («Sign in with SimpleLogin») |
| **SCIM 2.0** | ❌ | Нет |
| **LDAP** | ❌ | Нет |
| **2FA** | ✅ | TOTP + WebAuthn |

---

### AnonAddy (addy.io)

| | |
|---|---|
| Сайт | https://addy.io/ |
| GitHub | https://github.com/anonaddy/anonaddy (~4.8k ⭐) |
| Язык | PHP (Laravel) |
| Лицензия | AGPL-3.0 |
| Docker | ✅ |

Безлимитные email-алиасы. Отправка/ответ анонимно. Кастомные домены с catch-all. GPG/OpenPGP шифрование. Расширения для браузеров. Приложения iOS/Android. Developer API. Rspamd.

**Плюсы:** Щедрая бесплатная поддержка. Полностью open-source. GPG — killer-фишка приватности.

**Минусы:** Self-hosting требует Postfix + PHP + Redis + MariaDB + Nginx. Нет IMAP.

**Статус:** Активен. 497 коммитов. Solo-разработчик.

---

## 3. Веб-клиенты (Webmail)

### Roundcube

| | |
|---|
| Сайт | https://roundcube.net/ |
| GitHub | https://github.com/roundcube/roundcubemail (~7.1k ⭐) |
| Язык | PHP (jQuery) |
| Лицензия | GPL-3.0 |
| Docker | ✅ `roundcube/roundcubemail` |

Drag-and-drop, треды. Полный MIME/HTML, несколько личностей. Адресная книга с LDAP, проверка орфографии. Elastic skin, глобальные IMAP-папки, ACL. PGP, кэширование, плагины.

**Плюсы:** Самое большое сообщество, самое зрелое (~20+ лет), больше всего плагинов.

**Минусы:** UI выглядит устаревшим. PHP, нет JMAP.

**Статус:** Активен. Последний релиз v1.7.3 (9 авг 2026).

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC-вход** | ✅ | Через плагины: [`pulsejet/roundcube-oidc`](https://github.com/pulsejet/roundcube-oidc) (1,281 установок), [`cymdeveloppement/roundcube-new-oidc`](https://github.com/CymDeveloppement/roundcube-new-oidc) (с OIDC logout + auto-redirect) |
| **OAuth2-вход** | ✅ | Нативная поддержка OAuth2, настраивается через `config.inc.php`. Работает с Authelia, Authentik, Keycloak и др. |
| **SAML** | ❌ | Нет |
| **IMAP-аутентификация** | ⚠️ | OIDC-плагины требуют один из 3 режимов: (1) Cleartext Password — IdP отдаёт пароль, (2) Master Password — один пароль на всех, (3) Master User — Dovecot master user. Без cleartext пароля OIDC-плагин не работает |

**Документация:**
- https://github.com/roundcube/roundcubemail/wiki/Configuration:-OAuth2
- https://www.authelia.com/integration/openid-connect/clients/roundcube/
- https://integrations.goauthentik.io/chat-communication-collaboration/roundcube/

---

### SnappyMail

| | |
|---|
| Сайт | https://snappymail.eu/ |
| GitHub | https://github.com/the-djmaze/snappymail (~1.7k ⭐) |
| Язык | PHP, JavaScript (KnockoutJS) |
| Лицензия | AGPL-3.0 |
| Docker | ✅ `djmaze/snappymail` |

Форк RainLoop, модернизированный. Без БД — файловый конфиг. OpenPGP.js v5, GnuPG, Mailvelope. Тёмная тема, Kolab groupware. Редактор Sieve. Service worker.

**Плюсы:** Экстремально лёгкий (~110KB gzipped). Приватность/GDPR. Быстрый мобильный UI.

**Минусы:** В основном solo-мейнтейнер. Плагины RainLoop не совместимы. Только IMAP.

**Статус:** Активен. 7,184 коммитов.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC-вход** | ⚠️ | Через плагин `proxy-auth`. Читает HTTP-заголовок (Remote-User) от внешнего прокси (Authelia, Authentik). Логинится в IMAP через Dovecot master user. НЕ нативный OIDC-флоу |
| **OAuth2-вход** | ⚠️ | Только для подключения Outlook-аккаунтов (не для SSO) |
| **SAML** | ❌ | Нет |

**Ограничения:** Требует настройки Dovecot master user + внешний прокси для аутентификации. Нет нативного discovery/authorization code flow.

---

### Cypht

| | |
|---|
| Сайт | https://cypht.org/ |
| GitHub | https://github.com/cypht-org/cypht (~1.7k ⭐) |
| Язык | PHP |
| Лицензия | LGPL-2.1 |
| Docker | ✅ `cypht/cypht` |

Единый inbox для всех аккаунтов (IMAP, JMAP, EWS). Объединённый email + RSS. Sieve. Модульная система. Gmail OAuth, Outlook OAuth. LDAP, БД, IMAP для аутентификации.

**Плюсы:** Настоящий multi-аккаунтный агрегатор. Поддерживает JMAP и EWS в дополнение к IMAP.

**Минусы:** Маленькое сообщество. UI менее полированный. Документация скудная.

**Статус:** Активен. 7,534 коммитов.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC-вход** | ❌ | Открытый feature request [cypht-org/cypht#786](https://github.com/cypht-org/cypht/issues/786) (с окт 2023). Нет реализации |
| **OAuth2-вход** | ⚠️ | Только для подключения Gmail/Outlook (не для входа в Cypht) |
| **SAML** | ❌ | Нет |
| **JMAP** | ✅ | Как клиент для подключения JMAP-аккаунтов |
| **EWS** | ✅ | Exchange Web Services |

---

### Bulwark

| | |
|---|
| Сайт | https://bulwarkmail.org/ |
| GitHub | https://github.com/bulwarkmail/webmail (~1k ⭐) |
| Язык | TypeScript, Next.js, JMAP |
| Лицензия | AGPL-3.0 |
| Docker | ✅ `ghcr.io/bulwarkmail/webmail` |

JMAP-нативный webmail для Stalwart. Почта, Календарь, Контакты, Файлы. Серверная thread-обработка, push (без поллинга). OAuth2/OIDC, S/MIME, Sieve. Плагины + темы. PWA. Мобильное приложение (React Native).

**Плюсы:** Самая современная архитектура (2026, JMAP с нуля). Экстремально быстрый. Красивый UI. 37 релизов с марта 2026.

**Минусы:** Работает только с Stalwart (JMAP). Очень новый проект. Нет IMAP.

**Статус:** Активен. 1,497 коммитов с мар 2026.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC-вход** | ✅✅ | Нативный. Полный Authorization Code + PKCE. Настройка через env-переменные. `OAUTH_ONLY` режим (скрывает форму логина). Поддержка iframe embedding с `postMessage` bridge |
| **OAuth2** | ✅✅ | Нативный. PKCE state в encrypted httpOnly cookie |
| **SAML** | ❌ | Нет |
| **2FA** | ✅ | TOTP + OIDC |
| **S/MIME** | ✅ | |
| **Sieve** | ✅ | |

**Документация:**
- https://bulwarkmail.org/docs/guides/embedded-sso
- https://bulwarkmail.org/docs/getting-started/configuration/environment-reference

---

### Nextcloud Mail

| | |
|---|
| Сайт | https://nextcloud.com/mail/ |
| GitHub | https://github.com/nextcloud/mail (~1k ⭐) |
| Язык | PHP (Horde), Vue.js, TypeScript |
| Лицензия | AGPL-3.0 |
| Docker | ✅ (через Nextcloud) |

Глубокая интеграция с Nextcloud (Contacts, Calendar, Files, Tasks). Несколько почтовых аккаунтов, unified inbox. S/MIME + Mailvelope PGP. Треды, управление почтой. AI priority inbox и summaries.

**Плюсы:** Бесшовная интеграция с Nextcloud. Активная разработка.

**Минусы:** Требует Nextcloud — нельзя использовать отдельно. Нет JMAP. Медленно с большими ящиками.

**Статус:** Активен. 18,163 коммитов.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC-вход** | ✅ | Через приложение Nextcloud `user_oidc` или `oidc_login`. SSO работает на уровне Nextcloud |
| **OAuth2** | ⚠️ | Только для Gmail и Microsoft/Office 365 почтовых аккаунтов. Кастомные OIDC-провайдеры для почтового бэкенда НЕ поддерживаются ([nextcloud/mail#12491](https://github.com/nextcloud/mail/issues/12491)) |
| **SAML** | ✅ | Через Nextcloud SSO & SAML app |

---

### SOGo (используется Mailcow)

| | |
|---|
| Сайт | https://www.sogo.nu/ |
| Язык | Objective-C /greSQL |
| Лицензия | LGPL-2.1 |

Groupware-клиент: почта, календарь, контакты. Совместим с Outlook (ActiveSync, CalDAV, CardDAV). WebUI + native-клиенты.

#### Поддержка стандартов

| Стандарт | Поддержка | Примечания |
|----------|-----------|------------|
| **OIDC** | ✅ (нативный) | SOGo имеет встроенную OIDC-поддержку: `SOGoAuthenticationType = openid`, `SOGoOpenIdConfigUrl`, `SOGoOpenIdClient`, `SOGoOpenIdClientSecret`, `SOGoOpenIdScope`, `SOGoOpenIdRedirectURI`. Поддерживает refresh tokens и logout |
| **SAML** | ✅ | Нативная поддержка |
| **Proxy Auth** | ✅ | В Mailcow используется именно этот механизм: аутентификация через Mailcow UI → redirect на SOGo без повторного входа |

**Важно:** В составе Mailcow нативный OIDC SOGo НЕ используется — только proxy auth.

---

## 4. Утилиты

### Mailpit (тестирование email)

| | |
|---|
| Сайт | https://mailpit.axllent.org/ |
| GitHub | https://github.com/axllent/mailpit (~10.1k ⭐) |
| Язык | Go (один бинарник) |
| Лицензия | MIT |
| Docker | ✅ `axllent/mailpit` |

SMTP-сервер (:1025) + веб-UI (:8025). Нулевые зависимости. HTML-проверка (с оценкой совместимости). Ссылочный чекер, SpamAssassin. Скриншоты. REST API. POP3, тэги, relay/forwarding. Webhooks, WebSocket.

**Плюсы:** Экстремально популярен. Идеален для CI/CD. Замена брошенному MailHog.

**Минусы:** НЕ webmail — только тестирование. Нет мульти-юзера.

**Статус:** Активен. 1,940 коммитов.

---

### Notifuse (рассылки)

| | |
|---|
| Сайт | https://notifuse.com/ |
| GitHub | https://github.com/Notifuse/notifuse (~2k ⭐) |
| Язык | Go + React, PostgreSQL |
| Лицензия | AGPL-3.0 |
| Docker | ✅ |

Визуальный MJML-конструктор. Кампании, расписание, A/B-тесты. 7 провайдеров отправки. Liquid-шаблоны. Автоматизация. Транзакционный API. Отслеживание. Multi-tenant. AI-ассистент.

**Плюсы:** Самая полная платформа для рассылок. Self-hosted Mailchimp/Brevo.

**Минусы:** Не принимает community PR. Требует PostgreSQL. Новее/Listmonk.

**Статус:** Активен. 1,257 коммитов.

---

## 5. Сравнение серверов: поддержка стандартов

| Сервер | OIDC | SCIM | LDAP | OAuth2 | SAML | WebAuthn | 2FA | JMAP | CalDAV |
|--------|------|------|------|--------|------|----------|-----|------|--------|
| **Stalwart** | ✅✅ провайдер + потребитель | ❌ | ✅ | ✅ провайдер | ❌ | ❌ | ⚠️ TOTP | ✅✅ полный | ✅ |
| **Mailcow** | ✅ потребитель (Keycloak/Generic) | ❌ (PR) | ✅ | ⚠️ для внешних приложений | ⚠️ сломан | ✅ | ✅ TOTP+WebAuthn+Yubi | ❌ | ✅ (SOGo) |
| **Mailu** | ❌ (через прокси) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (Radicale) |
| **Mail-in-a-Box** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ TOTP (админка) | ❌ | ✅ (Nextcloud) |
| **Mox** | ❌ | ❌ | ❌ | ⏳ roadmap | ❌ | ❌ | ❌ | ⏳ roadmap | ❌ |
| **Postal** | ✅ потребитель | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Dovel** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

## 6. Сравнение клиентов: поддержка SSO

| Клиент | OIDC-вход | OAuth2 | SAML | Качество SSO | Примечания |
|--------|-----------|--------|------|-------------|------------|
| **Bulwark** | ✅✅ нативный (PKCE) | ✅ нативный | ❌ | ⭐⭐⭐⭐⭐ | Purpose-built для SSO. OAUTH_ONLY режим. Идеально с Stalwart |
| **Roundcube** | ✅ через плагины | ✅ нативный | ❌ | ⭐⭐⭐⭐ | Множество зрелых плагинов. OIDC требует master user |
| **SOGo** | ✅ нативный | ❌ | ✅ | ⭐⭐⭐⭐ | Нативный OIDC работает standalone. В Mailcow — proxy auth |
| **Nextcloud Mail** | ✅ через NC | ⚠️ Gmail/MS only | ✅ через NC | ⭐⭐⭐ | SSO на уровне Nextcloud. Ограничен для почтового бэкенда |
| **SnappyMail** | ⚠️ proxy-auth only | ⚠️ Outlook only | ❌ | ⭐⭐ | Требует proxy + master user. Не нативный OIDC |
| **Cypht** | ❌ | ⚠️ Gmail/Outlook only | ❌ | ⭐ | Feature request открыт с 2023. Нет SSO |

---

## 7. Сравнение: полная таблица протоколов

| Сервер | IMAP | SMTP | POP3 | JMAP | CalDAV | CardDAV | WebDAV | ActiveSync | Sieve | Webmail |
|--------|------|------|------|------|--------|---------|--------|------------|-------|---------|
| **Stalwart** | ✅ | ✅ | ✅ | ✅✅ | ✅ | ✅ | ✅ | ❌ | ✅✅ | ❌ (Bulwark) |
| **Mailcow** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ (SOGo) |
| **Mailu** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ (Roundcube) |
| **Mail-in-a-Box** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ (Roundcube) |
| **Mox** | ✅✅ (IMAP4rev2) | ✅ | ❌ | ⏳ | ⏳ | ⏳ | ⏳ | ❌ | ⏳ | ✅ |
| **Postal** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

---

## 8. Сравнение: безопасность email (SPF/DKIM/DMARC/etc.)

| Сервер | SPF | DKIM | DMARC | ARC | DANE | MTA-STS | TLS-RPT | Шифрование на диске |
|--------|-----|------|-------|-----|------|---------|---------|---------------------|
| **Stalwart** | ✅ | ✅ (ротация ключей) | ✅ (отчёты) | ✅ | ✅ | ✅ | ✅ | ✅ S/MIME + OpenPGP |
| **Mailcow** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (с 2025-09) | ✅ | ❌ |
| **Mailu** | ✅ | ✅ | ✅ | ⚠️ | ✅ (с 1.9) | ✅ (с 1.9) | ❌ | ❌ |
| **Mail-in-a-Box** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **Mox** | ✅ | ✅ (RSA + ed25519) | ✅ (отчёты) | ⏳ | ✅ | ✅ | ✅ | ❌ |
| **Postal** | ✅ | ✅ | ⚠️ только DNS | ❌ | ❌ | ❌ | ❌ | ❌ |

---

## 9. Рекомендации

### Лучшие стеки для почтовой инфраструктуры

| Сценарий | Сервер | Клиент | Примечания |
|----------|--------|--------|------------|
| **Максимальная совместимость со стандартами** | Stalwart + Bulwark | Bulwark (JMAP) | OIDC провайдер+потребитель, JMAP, CalDAV/CardDAV/WebDAV, шифрование на диске, кластеризация. Pre-1.0 |
| **Docker + groupware (Outlook-совместимый)** | Mailcow + SOGo | SOGo webmail | CalDAV/CardDAV/ActiveSync. OIDC через Keycloak. WebAuthn/FIDO2. Самый зрелый Docker-стек |
| **Минимальное обслуживание** | Mox | SnappyMail | Go-бинарник + PHP webmail. Без OIDC (пока). Минимальные ресурсы. MIT |
| **Транзакционная почта** | Postal | N/A | Self-hosted SendGrid. OIDC для входа. Не для персональной почты |
| **Мульти-аккаунтный агрегатор** | Любой IMAP-сервер | Cypht | Unified inbox IMAP/JMAP/EWS. Без SSO |
| **Простота above all** | Mail-in-a-Box | Roundcube (встроенный) | Без Docker, Ubuntu only, zero config. Без каких-либо SSO-стандартов |
| **Алиасы / приватность** | — | — | SimpleLogin или AnonAddy поверх любого сервера |

### Топ-3 для homelab с ZITADEL

Учитывая текущую архитектуру homelab (ZITADEL + OAuth2 Proxy), оптимальные варианты:

1. **Stalwart + Bulwark** — Единственный почтовый сервер, который сам является OIDC-провайдером и полноценно работает как OIDC-потребитель. Bulwark имеет нативный OIDC с PKCE. Stalwart → ZITADEL (OIDC) для аутентификации → Bulwark (OIDC) для веб-доступа. JMAP вместо IMAP. Календарь, контакты, файлы. Шифрование на диске.

2. **Mailcow + SOGo** — Самый зрелый Docker-стек. OIDC через Keycloak или Generic-OIDC (ZITADEL). WebAuthn/FIDO2 для 2FA. SOGo через proxy auth. Outlook-совместимый groupware. Зрелое сообщество, профессиональная поддержка.

3. **Mailu + Roundcube** — Гибкий, но слабый в SSO. Требует oauth2-proxy перед Mailu + Roundcube с OIDC-плагином. Много ручной настройки. MIT-лицензия, но дороже по времени.

### Критерий выбора: SSO-интеграция

| Критерий | Stalwart | Mailcow | Mailu | Mox | Mail-in-a-Box |
|----------|----------|---------|-------|-----|---------------|
| OIDC с ZITADEL (нативный) | ✅ | ✅ (Generic-OIDC) | ❌ | ❌ | ❌ |
| OIDC для webmail | ✅ (Bulwark) | ⚠️ (SOGo proxy) | ❌ | ❌ | ❌ |
| SCIM (когда появится) | ❌ | ⏳ PR | ❌ | ❌ | ❌ |
| Back-Channel Logout | ❌ | ❌ | ❌ | ❌ | ❌ |
| App Passwords для IMAP/SMTP | ✅ | ✅ (OIDC-пользователи) | ✅ | ✅ | ✅ |
| LDAP (альтернатива OIDC) | ✅ | ✅ | ❌ | ❌ | ❌ |

---

*Данные собраны 2026-08-19 из selfh.st/apps, GitHub, официальной документации проектов и спецификаций RFC.*
