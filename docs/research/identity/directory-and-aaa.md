# Каталог и AAA: LDAP, Kerberos, RADIUS

Дата проверки: 2026-11-21.

Дополнение к [idp-comparison-matrix.md](idp-comparison-matrix.md). Тот документ
отвечает на вопрос «кто вошёл в веб-приложение» (OIDC/SAML, ZITADEL). Этот —
про слой ниже: **где хранятся учётки** (LDAP), **как доказывается личность без
пароля** (Kerberos) и **как пускают в сеть** (RADIUS). Пересечение одно: все
три умеют быть бэкендом для IdP и наоборот.

Практической цели «внедрить» у документа нет. Задача — понять технологию,
сравнить реализации и заранее знать цену, если в стенде появится потребитель:
NAS с SMB, WiFi с 802.1X, NFSv4 с krb5.

## Вывод

1. **LDAP — протокол доступа к каталогу, а не сервер и не IdP.** «Поставить
   LDAP» бессмысленно: ставится конкретная реализация (OpenLDAP, 389 DS,
   Samba AD DC), и у неё свои правила записи, репликации и схемы.
2. **Три протокола решают три разные задачи и не заменяют друг друга.**
   LDAP — «дай атрибуты объекта», Kerberos — «выдай билет на сервис», RADIUS —
   «пусти этот MAC/EAP в VLAN». Попытка закрыть одну задачу другим протоколом
   — источник большинства архитектурных ошибок в этой теме.
3. **Active Directory — эталонная связка всех трёх плюс DNS.** AD = LDAP
   (каталог) + Kerberos (билеты) + DNS (SRV-записи KDC) + SMB (файлы) + PAC
   (группы в билете). Поэтому «сделать как AD» без Kerberos и DNS не
   получается.
4. **FreeIPA — это «AD для Linux» из готовых компонентов**: 389 Directory
   Server + MIT Kerberos + BIND + Dogtag CA + SSSD. Полный стек, полный вес,
   полная цена эксплуатации.
5. **В homelab LDAP нужен только под конкретного потребителя.** Пока такого
   нет — ZITADEL закрывает веб-SSO, а LDAP добавляет вторую базу учёток.
   Триггеры: SMB-шара с AD-аутентификацией, Synology/TrueNAS, SSSD на узлах,
   старые приложения без OIDC.
6. **«LDAP-фасады» — не каталоги.** Kanidm отдаёт LDAP только на чтение и
   только LDAPS; Authentik LDAP outpost — bind+search через flow; lldap —
   упрощённая модель; glauth — каталог из конфига. Все четыре годятся, чтобы
   накормить клиента, и не годятся как единственное хранилище учёток.
7. **Kerberos в Kubernetes не используется.** kube-apiserver аутентифицирует
   x509, bearer-токенами, OIDC, webhook и authenticating proxy; SPNEGO/Kerberos
   в этом списке нет. Kerberos в homelab появляется только вместе с SMB,
   NFSv4 (`sec=krb5*`) или SSH GSSAPI.
8. **RADIUS нужен ровно для одного сценария — 802.1X/VPN.** Домашняя WiFi без
   Enterprise-режима в нём не нуждается. FreeRADIUS 3.2.10 — актуальная
   стабильная ветка; **4.0 так и не выпущен** (на 2026-11-21 нет ни одного
   релизного тега 4.x).
9. **Цена в ресурсах различается на два порядка.** lldap/glauth/Dex — десятки
   мегабайт RSS; Keycloak официально требует лимит от 750 МБ, рекомендуется
   2 ГБ; PacketFence — от 8 ГБ. Полный FreeIPA — это 389 DS, KDC, BIND и
   Java-CA в одном флаконе.
10. **Главный риск — не протокол, а два источника правды.** Как только LDAP и
    OIDC-провайдер живут раздельно, появляются расхождения в учётках, паролях
    и группах. Хеши паролей между ними не синхронизируются (и не должны),
    поэтому выбирается один владелец учёток, а второй слой работает фасадом
    или федерацией.
11. **Для этого стенда сейчас — ничего не ставить.** ZITADEL уже закрывает
    SSO; LDAP/Kerberos/RADIUS добавляют сервисы без потребителя. Решение
    пересматривается при появлении конкретного сценария (§8).

## 1. Границы: каталог, IdP, AAA

| Слой | Что хранит/делает | Протоколы | Типичные продукты |
| --- | --- | --- | --- |
| **Каталог** | дерево объектов и атрибутов: люди, группы, хосты, сервисы | LDAP (RFC 4511), LDIF, схемы | OpenLDAP, 389 DS, AD, Samba AD DC |
| **IdP / брокер** | аутентификация и выпуск утверждений для приложений | OIDC, OAuth 2.0, SAML 2.0, WS-Fed | ZITADEL, Keycloak, Authentik, Dex |
| **AAA для сети** | «пустить/не пустить» устройство или сессию | RADIUS (RFC 2865/2866), EAP, 802.1X | FreeRADIUS, PacketFence, ISE |
| **Билеты** | доказательство личности сервису без передачи пароля | Kerberos 5 (RFC 4120), SPNEGO | MIT krb5, Heimdal, AD, Samba |

Что важно не путать:

- **LDAP ≠ аутентификация.** LDAP умеет bind (проверить пароль), но его
  основная работа — поиск и чтение атрибутов. Приложение, которому нужен
  только вход, часто проще подключить к OIDC.
- **Kerberos ≠ LDAP.** AD держит учётки в LDAP, а билеты выдаёт KDC; это два
  разных сервиса с разными портами и разными базами (в AD — одна, но логически
  это два протокола поверх неё).
- **RADIUS ≠ IdP.** RADIUS не умеет OIDC и не хранит пользователей; он
  проксирует проверку пароля/EAP в каталог или IdP.

### 1.1 Термины

| Термин | Значение | Источник |
| --- | --- | --- |
| **DIT** | Directory Information Tree — иерархия записей | [RFC 4512 §2](https://www.rfc-editor.org/rfc/rfc4512) |
| **DN / RDN** | полное имя записи и его первый компонент (`cn=art,ou=people,dc=example,dc=com`) | [RFC 4512 §2](https://www.rfc-editor.org/rfc/rfc4512) |
| **Атрибут** | типизированное значение с набором допустимых синтаксисов и matching rules | [RFC 4512 §2.2](https://www.rfc-editor.org/rfc/rfc4512), [RFC 4517](https://www.rfc-editor.org/rfc/rfc4517) |
| **objectClass** | набор обязательных и необязательных атрибутов записи | [RFC 4512 §2.4](https://www.rfc-editor.org/rfc/rfc4512) |
| **Схема** | определения objectClass, атрибутов, синтаксисов, matching rules | [RFC 4519](https://www.rfc-editor.org/rfc/rfc4519) |
| **OID** | числовой идентификатор элемента схемы (`2.5.4.3` = `cn`) | [RFC 4512 §1.4](https://www.rfc-editor.org/rfc/rfc4512) |
| **Root DSE** | пустой DN, отдающий возможности сервера (namingContexts, supportedControl) | [RFC 4512 §5.1](https://www.rfc-editor.org/rfc/rfc4512) |
| **subschemaSubentry** | запись со схемой, которую реально обслуживает сервер | [RFC 4512 §4.2](https://www.rfc-editor.org/rfc/rfc4512) |
| **Operational attributes** | служебные атрибуты (entryUUID, createTimestamp), не отдаются без запроса | [RFC 3673](https://www.rfc-editor.org/rfc/rfc3673) |
| **Referral** | «эта часть дерева обслуживается другим сервером» | [RFC 4511 §4.1.10](https://www.rfc-editor.org/rfc/rfc4511) |
| **Bind** | операция установления личности соединения | [RFC 4511 §4.2](https://www.rfc-editor.org/rfc/rfc4511) |
| **SASL** | сменные механизмы аутентификации внутри LDAP | [RFC 4422](https://www.rfc-editor.org/rfc/rfc4422), [RFC 4513 §5.2](https://www.rfc-editor.org/rfc/rfc4513) |
| **Keytab** | файл с ключами principals для сервиса | [MIT krb5 docs](https://web.mit.edu/kerberos/krb5-latest/doc/basic/keytab_def.html) |
| **TGT** | Ticket-Granting Ticket — билет на получение билетов | [RFC 4120 §1.2](https://www.rfc-editor.org/rfc/rfc4120) |
| **PAC** | структура в билете AD с SID и группами пользователя | [MS-PAC](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-pac/) |
| **NAS** | Network Access Server — клиент RADIUS (AP, VPN, коммутатор) | [RFC 2865 §1](https://www.rfc-editor.org/rfc/rfc2865) |
| **Supplicant / Authenticator** | клиент 802.1X и точка доступа/коммутатор, которые его пускают | [IEEE 802.1X-2020](https://standards.ieee.org/ieee/802.1X/7345/) |

## 2. LDAP: протокол

### 2.1 Модель данных

LDAP — не реляционная БД и не «дерево папок». Это иерархия записей, у каждой
записи есть DN, набор objectClass и атрибуты. Атрибут многозначный по
умолчанию: `mail` может встречаться несколько раз, порядок не гарантирован.
Схема задаёт, какие атрибуты обязательны, какие допустимы и какие значения
считаются равными (matching rules) — от этого зависит, найдёт ли фильтр запись.

Практические следствия:

- **Фильтр — не SQL.** `(&(objectClass=person)(uid=art))` вычисляется по
  индексам; `(cn=*art*)` без индекса превращается в полный перебор.
- **DN меняется, entryUUID — нет.** Поэтому репликация и ссылки опираются на
  `entryUUID`, а не на DN ([RFC 4533 §2](https://www.rfc-editor.org/rfc/rfc4533)).
- **Схема расширяема, но не бесплатно.** Свой objectClass — это OID, файл
  схемы и проверка на всех репликах; «просто добавить атрибут» в OpenLDAP
  нельзя без правки схемы.

### 2.2 Операции

| Операция | Что делает | Замечание |
| --- | --- | --- |
| `bind` / `unbind` | установить/снять личность соединения | simple, SASL, anonymous |
| `search` | найти записи по base/scope/filter/attrs | основная операция, 90 % трафика |
| `compare` | проверить конкретное значение атрибута | редко используется клиентами |
| `add` / `delete` | создать/удалить запись | требуют прав и схемы |
| `modify` | изменить атрибуты | `add`/`delete`/`replace` значений |
| `modifyDN` | переименовать/переместить запись | дорогая операция на больших поддеревьях |
| `abandon` | отменить операцию | асинхронность протокола |
| `extended` | расширенные операции (StartTLS, WhoAmI, Password Modify) | [RFC 4511 §4.12](https://www.rfc-editor.org/rfc/rfc4511) |

Протокол асинхронный: клиент может отправить несколько запросов в одном
соединении и получать ответы в произвольном порядке, соотнося их по messageID.
Именно поэтому LDAP-клиенты так чувствительны к таймаутам и пулам соединений.

### 2.3 Аутентификация

| Механизм | Как работает | Риск/ограничение |
| --- | --- | --- |
| **Anonymous bind** | пустой DN и пароль | сервер может запретить; часто включён для Root DSE |
| **Simple bind** | DN + пароль в открытом виде | без TLS пароль виден в сети; RFC 4513 прямо предупреждает ([§5.1.1](https://www.rfc-editor.org/rfc/rfc4513)) |
| **SASL EXTERNAL** | личность из TLS-клиентского сертификата | нужен mTLS и маппинг сертификата на DN |
| **SASL GSSAPI** | Kerberos-билет вместо пароля | нужен KDC и SPN сервиса |
| **SASL SCRAM** | challenge-response, пароль не передаётся | [RFC 5802](https://www.rfc-editor.org/rfc/rfc5802), [RFC 7677](https://www.rfc-editor.org/rfc/rfc7677); поддержка зависит от сервера |
| **Proxy authorization** | сервис действует от имени пользователя | требует прав `authzTo`/`authzFrom` |

Ключевая практика: **simple bind только по TLS**. Это же требование повторяют
почти все проекты — Dex пишет, что при подключении на 389 «администраторы
активно утекают пароли» ([Dex LDAP connector](https://dexidp.io/docs/connectors/ldap/)).

### 2.4 Транспорт и TLS

| Порт | Назначение | Примечание |
| --- | --- | --- |
| 389/tcp | LDAP, обычно с StartTLS | IANA `ldap` |
| 636/tcp | LDAPS (TLS с первого байта) | IANA `ldaps` |
| unix-сокет | LDAPI (`ldapi:///`) | локальное администрирование, SASL EXTERNAL по uid |

StartTLS и LDAPS — разные вещи. StartTLS позволяет начать открытым текстом и
апгрейдиться; LDAPS шифрует всё соединение сразу. Kanidm, например, StartTLS
принципиально не поддерживает, считая его неремонтируемо небезопасным
([Kanidm LDAP](https://kanidm.github.io/kanidm/stable/integrations/ldap.html)).
Это не универсальное мнение, но показывает, что «LDAP+StartTLS» — не
автоматически безопасная комбинация.

### 2.5 Controls и расширения

Controls — способ расширить операцию, не меняя протокол. Клиент объявляет их
в запросе, сервер — в ответе; неподдерживаемый critical control даёт ошибку.

| Control / расширение | RFC | Зачем |
| --- | --- | --- |
| Paged results | [RFC 2696](https://www.rfc-editor.org/rfc/rfc2696) | постраничный поиск вместо обрыва по size limit |
| Server-side sort | [RFC 2891](https://www.rfc-editor.org/rfc/rfc2891) | сортировка на сервере |
| Password Modify | [RFC 3062](https://www.rfc-editor.org/rfc/rfc3062) | смена пароля расширенной операцией |
| Who Am I? | [RFC 4532](https://www.rfc-editor.org/rfc/rfc4532) | узнать, кем сервер считает соединение |
| Content Sync (syncrepl) | [RFC 4533](https://www.rfc-editor.org/rfc/rfc4533) | репликация «pull/push» |
| Transactions | [RFC 5805](https://www.rfc-editor.org/rfc/rfc5805) | атомарная группа операций |
| All operational attributes | [RFC 3673](https://www.rfc-editor.org/rfc/rfc3673) | `+` в списке атрибутов |
| ManageDsaIT | [RFC 3296](https://www.rfc-editor.org/rfc/rfc3296) | работа с referral как с обычными записями |
| Assertion | [RFC 4528](https://www.rfc-editor.org/rfc/rfc4528) | условная запись («измени, если значение равно») |

Password policy (`ppolicy`) — не RFC, а draft, реализованный по-разному:
в OpenLDAP это overlay, в 389 DS — атрибуты политики, в AD — доменная
политика. Переносимость между серверами здесь плохая.

### 2.6 Схемы

| Схема | Что даёт | RFC |
| --- | --- | --- |
| core | `top`, `person`, `organizationalUnit`, `groupOfNames` | [RFC 4519](https://www.rfc-editor.org/rfc/rfc4519) |
| cosine | `device`, `room`, `document` и прочая «офисная» модель | [RFC 4524](https://www.rfc-editor.org/rfc/rfc4524) |
| inetOrgPerson | `uid`, `mail`, `displayName`, `jpegPhoto` | [RFC 2798](https://www.rfc-editor.org/rfc/rfc2798) |
| nis | `posixAccount`, `posixGroup`, `uidNumber`, `gidNumber` | [RFC 2307](https://www.rfc-editor.org/rfc/rfc2307) |
| nis bis | группы через `member`, а не `memberUid` | [draft-ietf-ldapext-rfc2307bis](https://datatracker.ietf.org/doc/html/draft-ietf-ldapext-rfc2307bis-04) |
| certificates | `userCertificate`, `cACertificate` | [RFC 4523](https://www.rfc-editor.org/rfc/rfc4523) |

Практика: POSIX-клиенты (SSSD, nslcd, Samba) ожидают `posixAccount` и
`posixGroup`, а веб-приложения — `inetOrgPerson`. Отсюда вечная проблема
«одна учётка — два набора атрибутов» и костыли вроде `memberUid` против
`member`.

### 2.7 Репликация

| Модель | Как работает | Где |
| --- | --- | --- |
| **syncrepl** | consumer тянет изменения по RFC 4533; провайдер не настраивается | OpenLDAP |
| **delta-syncrepl** | изменения из accesslog, а не целые записи | OpenLDAP |
| **multi-provider / mirror** | несколько провайдеров, записи идут во все | OpenLDAP |
| **multi-supplier (MMR)** | асинхронная репликация «каждый с каждым» | 389 DS, FreeIPA |
| **DRS** | протокол репликации AD между DC | AD, Samba AD DC |

OpenLDAP честно пишет, что multi-provider **не** даёт load balancing и ломает
гарантии консистентности модели каталога; рекомендуемый компромисс — mirror
mode с внешним балансировщиком, который направляет записи только в один узел
([Admin Guide §18.2](https://www.openldap.org/doc/admin26/replication.html)).
Это важная поправка к распространённому «сделаем active-active».

### 2.8 Чем AD-LDAP отличается от «просто LDAP»

Active Directory — LDAPv3-совместимый каталог с расширениями Microsoft:

- **SID вместо произвольных групп.** Членство в группе едет в PAC, а не
  вычисляется клиентом по `memberOf`.
- **Схема и OID свои**, часть атрибутов (`userPrincipalName`,
  `msDS-KeyVersionNumber`, `objectSid`) не имеет аналогов в RFC-схемах.
- **Kerberos обязателен** для полноценной работы: SMB, GPO, вход Windows.
- **LDAP-контролы и расширения неполные**: часть RFC-расширений не реализована,
  часть ведёт себя иначе. Клиент, написанный «под OpenLDAP», не гарантирует
  работу с AD, и наоборот.
- **Анонимный доступ** по умолчанию ограничен, а простые bind-ы часто
  запрещены политикой.

Поэтому «подключить AD как LDAP» — отдельная задача с маппингом атрибутов
(пример конфигурации есть у [Dex](https://dexidp.io/docs/connectors/ldap/)).

### 2.9 Клиентская сторона

| Клиент | Что делает | Когда нужен |
| --- | --- | --- |
| **SSSD** | NSS/PAM-провайдер, кеш, офлайн-вход, поддержка LDAP/Kerberos/AD/IPA | Linux-хосты в домене; основной путь |
| **nss-pam-ldapd (nslcd)** | простой NSS/PAM через LDAP | legacy, без Kerberos |
| **winbind** | AD-членство для Samba и NSS | SMB-серверы |
| **libldap / JLDAP / go-ldap** | клиентские библиотеки | приложения |
| **ldapsearch / ldapwhoami** | отладка | всегда |

SSSD кеширует и умеет работать при недоступном каталоге; nslcd — нет.
Для homelab это разница между «вход работает, пока жива сеть» и «вход
работает всегда».

## 3. Реализации

### 3.1 Полноценные каталоги

| Продукт | Версия (2026-11-21) | Язык | Лицензия | Запись | Репликация | MFA | TLS | ★ GitHub |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **OpenLDAP** | 2.7.2 (feature), 2.6.16 (LTS) | C | OpenLDAP PL | полная | syncrepl, delta, multi-provider, mirror | нет (только SASL/плагины) | LDAPS, StartTLS | 612 |
| **389 Directory Server** | 3.3.1 | C | GPLv3 | полная | multi-supplier | нет (плагины) | LDAPS, StartTLS, SASL | 301 |
| **FreeIPA** | 4.13.5 | Python + C | GPLv3 | полная | multi-master (389 DS) | Kerberos, OTP | LDAPS, Kerberos | 1 302 |
| **Samba AD DC** | 4.25.1 | C | GPLv3 | полная | DRS multi-master | Kerberos | LDAPS, Kerberos | 1 154 |
| **Microsoft AD** | Windows Server | — | proprietary | полная | DRS multi-master | Kerberos, smart card | LDAPS, Kerberos | — |
| **ApacheDS** | 2.0.0.AM27 | Java | Apache-2.0 | полная | есть (2.0) | Kerberos 5 | LDAPS, StartTLS | 189 |
| **OpenDJ (OpenIdentityPlatform)** | 5.2.0 | Java | CDDL | полная | multi-master | SASL, сертификаты | LDAPS, StartTLS | 445 |

★ — звёзды GitHub на 2026-11-21. Это мера внимания, а не распространённости:
OpenLDAP и AD стоят в продакшене без звёзд, а популярный репозиторий может
быть популярен как учебный.


Коротко по каждому:

**OpenLDAP.** Эталон реализации протокола. Основной бэкенд — `mdb` (LMDB),
официально «recommended primary backend», заменивший BerkeleyDB-бэкенды
([Admin Guide §11.3](https://www.openldap.org/doc/admin26/backends.html)).
Распространяется **только исходниками** — пакеты собирает дистрибутив
([openldap.org/download](https://www.openldap.org/software/download/)).
Плюсы: минимальный вес, полный контроль, предсказуемость. Минусы: всё руками —
схемы, ACL, репликация, бэкапы; нет UI и нет MFA из коробки. Репликация
настраивается на consumer, провайдер часто не трогается вовсе.

**389 Directory Server.** Промышленный каталог Red Hat (бывший Fedora DS).
C, а не Java — Java только у старой консоли. Ключевое отличие от OpenLDAP —
ACI (access control instructions) как первоклассная модель, multi-supplier
репликация, богатая схема и инструменты (`dsctl`, `dsconf`, `dsidm`).
Требовательнее к памяти, чем slapd, но заметно проще в эксплуатации.

**FreeIPA.** Не «ещё один LDAP», а интегрированный IDM: 389 DS + MIT Kerberos
+ NTP + BIND + Dogtag CA + SSSD, с CLI, Web UI и API
([freeipa.org](https://www.freeipa.org/)). Даёт то, чего нет у голого LDAP:
хост-энроллмент, HBAC, sudo-правила, SELinux-маппинг, trust с AD. Цена —
полноценный сервер с systemd, собственным DNS и CA; в контейнере это
неестественный режим.

**Samba AD DC.** Единственная open-source реализация AD-контроллера: LDAP,
Kerberos, DNS, SMB и DRS в одном процессе
([samba.org](https://www.samba.org/), [README](https://github.com/samba-team/samba)).
Нужен, когда клиенты — Windows или когда требуется AD-совместимость (GPO,
RSAT). Не нужен, если все клиенты — Linux: FreeIPA даст то же самое дешевле
по сложности.

**Microsoft AD.** Эталон, с которым сравнивают всё остальное. Закрытый,
лицензируется по пользователям/ядрам, требует Windows Server. В homelab
попадает только как «пощупать в виртуалке».

**ApacheDS.** Java, LDAPv3-сертифицирован Open Group, умеет Kerberos 5 и
Change Password Protocol ([downloads](https://directory.apache.org/apacheds/downloads.html)).
Удобен для тестов и встраивания в Java-приложения; как основной каталог —
редкость.

**OpenDJ / PingDS.** Наследник Sun Directory Server. Открытая ветка
OpenIdentityPlatform (5.2.0), коммерческая — PingDS. Полный LDAPv3, Java,
multi-master. В homelab почти не встречается из-за веса JVM.

### 3.2 Облегчённые и «фасады»

| Продукт | Версия | Язык | Запись через LDAP | Репликация | Особенность |
| --- | --- | --- | --- | --- | --- |
| **Kanidm** | 1.12.1 | Rust | **нет**, только чтение | своя (реплика между серверами) | LDAPS only, без StartTLS; OIDC, RADIUS, SSH-ключи |
| **Authentik LDAP outpost** | 2026.8.6 | Python/Go | не задокументирована | нет (данные из Authentik) | bind через flow, MFA-код в пароле |
| **lldap** | 0.6.3 | Rust | ограниченная (смена пароля) | нет | Web UI, SQLite/MySQL/Postgres |
| **glauth** | 2.5.4 | Go | нет (каталог из конфига) | нет | TOML-конфиг, OTLP-трейсинг |
| **Dex** | 2.46.1 | Go | — (это клиент LDAP) | — | OIDC-брокер с LDAP-коннектором |
| **Keycloak** | 26.8.2 | Java | — (это клиент LDAP) | — | user federation, Kerberos feature |
| **ZITADEL** | 4.20.5 | Go | — (это клиент LDAP) | — | LDAP только как внешний IdP |

**Kanidm.** Современный IDM на Rust: OIDC, LDAPS, RADIUS, SSH-ключи, SCIM.
LDAP-интерфейс сознательно неполный: «simple bind and search», запись
отклоняется для всех, StartTLS не поддерживается, bind по POSIX-паролю даёт
права анонима, а повышенные права — только через api-token сервисной учётки
([Kanidm LDAP](https://kanidm.github.io/kanidm/stable/integrations/ldap.html)).
То есть это не замена OpenLDAP, а способ накормить legacy-клиента.

**Authentik LDAP outpost.** Каждый bind прогоняется через flow, поэтому
работают политики и MFA (код дописывается к паролю через `;`). Есть режимы
direct/cached для bind и search, LDAPS и StartTLS, права на полный поиск по
каталогу. Запись (add/modify/delete) в документации провайдера не описана —
считать его read-only.

**lldap.** «LDAP для тех, кто не хочет понимать LDAP»: веб-UI, группы, свои
атрибуты, GraphQL API, бэкенд SQLite/MySQL/Postgres. Модель упрощена:
`ou=people`, `ou=groups`, `memberOf`. Важное ограничение — сервисы, которым
нужны хеши паролей для собственной проверки, несовместимы; в README прямо
назван Synology ([lldap](https://github.com/lldap/lldap)).

**glauth.** Go-сервер, каталог описан в TOML. Хорош для dev/demo и
аутентификации в лаборатории, не для хранения учёток.

**Dex / Keycloak / ZITADEL.** Это не LDAP-серверы, а потребители: Dex —
OIDC-брокер с LDAP-коннектором, Keycloak — user federation (read-only,
writable, sync), ZITADEL — LDAP как внешний IdP (bind + search + маппинг
атрибутов, [docs](https://zitadel.com/docs/guides/integrate/identity-providers/ldap)).

### 3.3 Кто в self-hosted спрашивает LDAP

| Потребитель | Что использует | Нюанс |
| --- | --- | --- |
| **Synology DSM** | LDAP-домен | требует хеши паролей → lldap несовместим |
| **TrueNAS** | LDAP + Kerberos | для SMB/NFS с AD-подобным входом |
| **Samba** | LDAP/AD, winbind | как member server или AD DC |
| **Nextcloud** | LDAP-бэкенд пользователей | чувствителен к paged results и схеме |
| **GitLab** | LDAP (CE) | групповые фильтры, `uid`/`sAMAccountName` |
| **Grafana** | LDAP | маппинг групп в org role |
| **Vault** | LDAP auth method | редко нужен при наличии OIDC |
| **Jira/Confluence** | LDAP | типичный legacy-потребитель |
| **Proxmox** | LDAP/AD | плюс собственные realms |
| **pfSense/OPNsense** | LDAP для VPN/UI | часто проще RADIUS |
| **Zabbix** | LDAP | маппинг групп |
| **Linux-хосты (SSSD)** | LDAP + Kerberos | самый частый повод завести каталог |

Практический вывод: LDAP в homelab появляется не «потому что надо», а потому
что конкретный сервис без него не умеет. Список таких сервисов сокращается:
Nextcloud, Grafana, GitLab, Immich и большинство современных умеют OIDC.

## 4. Kerberos

### 4.1 Что это

Kerberos — протокол аутентификации с доверенной третьей стороной. Пользователь
один раз доказывает личность KDC и получает **TGT**; дальше на каждый сервис
он предъявляет **service ticket**, выданный KDC. Пароль по сети не ходит,
сервис не хранит пароль — только ключ в keytab.

Название — от Цербера, трёхголового пса: клиент, сервер и KDC доверяют друг
другу через KDC, а не напрямую.

| Понятие | Смысл |
| --- | --- |
| **Realm** | область доверия, обычно `EXAMPLE.COM` |
| **Principal** | `user@REALM` или `service/host@REALM` |
| **KDC** | Key Distribution Center: AS + TGS |
| **TGT** | билет, который клиент носит в credential cache |
| **Service ticket** | билет на конкретный сервис (`HTTP/web.example.com`) |
| **Keytab** | keytab-файл сервиса с его ключами и kvno |
| **kvno** | версия ключа; при смене пароля/ключа растёт |
| **Enctype** | алгоритм шифрования билета (aes256-cts-hmac-sha1-96 и т.д.) |

### 4.2 Обмен сообщениями

1. **AS-REQ/AS-REP** — клиент просит TGT, доказывая личность (пароль,
   keytab, PKINIT, preauth).
2. **TGS-REQ/TGS-REP** — клиент просит service ticket, предъявляя TGT.
3. **AP-REQ/AP-REP** — клиент предъявляет service ticket сервису; дальше
   приложение решает, что делать с identity.

Ошибки приходят как **KRB-ERROR** с кодом (`KDC_ERR_PREAUTH_FAILED`,
`KDC_ERR_S_PRINCIPAL_UNKNOWN`, `KRB_AP_ERR_SKEW`). Последняя — классика:
часы разошлись больше чем на 5 минут, и ничего не работает.

### 4.3 Криптография

| Enctype | RFC | Статус |
| --- | --- | --- |
| aes256-cts-hmac-sha1-96 | [RFC 3962](https://www.rfc-editor.org/rfc/rfc3962) | базовый |
| aes128-cts-hmac-sha1-96 | [RFC 3962](https://www.rfc-editor.org/rfc/rfc3962) | базовый |
| aes256-cts-hmac-sha2-384 | [RFC 8009](https://www.rfc-editor.org/rfc/rfc8009) | современный |
| rc4-hmac | [RFC 4757](https://www.rfc-editor.org/rfc/rfc4757) | legacy, нужен для старых клиентов |
| des / 3des | [RFC 6649](https://www.rfc-editor.org/rfc/rfc6649), [RFC 8429](https://www.rfc-editor.org/rfc/rfc8429) | deprecated |

RC4-HMAC — источник постоянной боли: старые клиенты и некоторые интеграции
требуют его, а включение ослабляет домен. В новом realm его включают только
под конкретный сервис.

### 4.4 Специфика AD

- **PAC** — расширение Microsoft: в билете едут SID пользователя, SID групп
  и подписанные структуры ([MS-PAC](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-pac/)).
  Без PAC Linux-сервис не узнает группы AD.
- **SPN** — `service/host`; для HTTP — `HTTP/host`, для SMB — `cifs/host`.
  Дубликат SPN ломает аутентификацию.
- **Делегирование**: unconstrained (опасно, билет дальше), constrained (S4U2Self/S4U2Proxy),
  resource-based (RBCD). В homelab не нужно, в enterprise — обязательный вопрос.
- **Salt и kvno** зависят от версии ОС и типа учётки; перенос keytab между
  доменами не работает.

### 4.5 Где Kerberos реально нужен

| Сценарий | Зачем | Альтернатива |
| --- | --- | --- |
| SMB (Samba/Windows) | SSO в шару | NTLM (слабее, отключается) |
| NFSv4 | `sec=krb5/krb5i/krb5p` | AUTH_SYS (uid/gid, без аутентификации) |
| SSH | GSSAPI-вход без пароля | ключи |
| HTTP | SPNEGO/Negotiate | OIDC |
| Kubernetes | **не используется** | OIDC, x509, webhook |

Kubernetes-аутентификация перечислена в
[docs](https://kubernetes.io/docs/reference/access-authn-authz/authentication/):
x509-клиентские сертификаты, bearer-токены, OIDC, webhook, authenticating
proxy, service account tokens. Kerberos там нет, и «сделать k8s-вход через
AD» — это всегда OIDC-прокси (Dex, Keycloak, ZITADEL) поверх AD.

### 4.6 Реализации

| Реализация | Версия | Особенность |
| --- | --- | --- |
| **MIT krb5** | 1.22.3 (2026-11-09) | эталон, KDC + клиент, основа FreeIPA |
| **Heimdal** | 7.8.0 (2022) | альтернативный KDC, историческая база Samba |
| **Samba (форк Heimdal)** | 4.25.1 | KDC внутри AD DC |
| **Microsoft AD** | Windows Server | KDC + PAC + политики |
| **Apache Kerby** | — | Java KDC для встраивания |

### 4.7 Эксплуатация

- **Время.** NTP обязателен; расхождение > 5 минут ломает вход.
- **DNS.** Клиенты находят KDC по SRV-записям `_kerberos._udp`,
  `_kerberos._tcp`; без них ничего не работает.
- **Keytab.** Хранится как секрет (Vault), ротация — вместе со сменой пароля
  сервисной учётки; старый kvno должен оставаться валидным на время
  перевыпуска.
- **Кросс-реалм.** Trust между realm — отдельная сущность со своими ключами;
  в homelab почти никогда не нужен.

## 5. RADIUS

### 5.1 Протокол

RADIUS — UDP-протокол «запрос-ответ» для аутентификации, авторизации и
учёта (AAA). Пакет: код, идентификатор, длина, 16-байтный authenticator и
список атрибутов TLV.

| Аспект | Деталь | Источник |
| --- | --- | --- |
| Порты | 1812/udp (auth), 1813/udp (accounting); 1645/1646 — legacy | [IANA](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml) |
| Транспорт | UDP, один запрос — один ответ | [RFC 2865](https://www.rfc-editor.org/rfc/rfc2865) |
| Защита пароля | XOR с MD5(secret + authenticator) | [RFC 2865 §5.2](https://www.rfc-editor.org/rfc/rfc2865) |
| Целостность | `Message-Authenticator` (HMAC-MD5) | [RFC 3579](https://www.rfc-editor.org/rfc/rfc3579) |
| Учёт | Accounting-Request/Response, Start/Stop/Interim | [RFC 2866](https://www.rfc-editor.org/rfc/rfc2866) |
| Смена сессии | CoA / Disconnect | [RFC 5176](https://www.rfc-editor.org/rfc/rfc5176) |
| Туннельные атрибуты | VLAN, Tunnel-Type/Medium/Private-Group-ID | [RFC 2868](https://www.rfc-editor.org/rfc/rfc2868) |
| Расширенные атрибуты | Vendor-Specific, extended type | [RFC 6929](https://www.rfc-editor.org/rfc/rfc6929) |
| Типы данных | text, string, address, integer, time | [RFC 8044](https://www.rfc-editor.org/rfc/rfc8044) |
| TLS-транспорт | RadSec, TCP/TLS 2083 | [RFC 6614](https://www.rfc-editor.org/rfc/rfc6614) |

Слабые места протокола известны: MD5-обфускация пароля, доверие к NAS по
IP+shared secret, отсутствие защиты от подмены ответа. Отсюда **BlastRADIUS**
(CVE-2024-3596) и обязательный `Message-Authenticator` в современных
сборках — FreeRADIUS добавил `require_message_authenticator` и
`limit_proxy_state` в 3.2.5 ([release notes](https://github.com/FreeRADIUS/freeradius-server/releases/tag/release_3_2_5)).

### 5.2 802.1X

| Роль | Кто это | Что делает |
| --- | --- | --- |
| **Supplicant** | ноутбук, телефон, принтер | предъявляет EAP-ответ |
| **Authenticator** | AP, коммутатор | EAPOL-обмен, решает «пустить в VLAN» |
| **Authentication server** | RADIUS | проверяет EAP, возвращает Accept/Reject + атрибуты |

MAB (MAC Authentication Bypass) — для устройств без supplicant: NAS
отправляет MAC как логин/пароль. Удобно и небезопасно (MAC подделывается);
используется как fallback с отдельным VLAN.

Динамический VLAN через `Tunnel-Private-Group-ID` — то, ради чего RADIUS
часто и ставят: один SSID, разные VLAN по группам.

### 5.3 EAP-методы

| Метод | Что внутри | RFC | Поддержка клиентами |
| --- | --- | --- | --- |
| **EAP-TLS** | взаимный TLS, сертификаты с обеих сторон | [RFC 5216](https://www.rfc-editor.org/rfc/rfc5216), [RFC 9190](https://www.rfc-editor.org/rfc/rfc9190) (1.3) | Windows, macOS, iOS, Android, Linux |
| **EAP-TTLS** | TLS-туннель, внутри пароль/MSCHAPv2 | [RFC 5281](https://www.rfc-editor.org/rfc/rfc5281) | почти всё |
| **PEAP** | TLS-туннель, внутри MSCHAPv2 | RFC нет (MS-PEAP) | «из коробки» на всех |
| **TEAP** | TLS-туннель + цепочки | [RFC 7170](https://www.rfc-editor.org/rfc/rfc7170) | ограниченно |
| **EAP-MSCHAPv2** | пароль по challenge-response | [RFC 2759](https://www.rfc-editor.org/rfc/rfc2759) | как внутренний метод |

Практика: «из коробки» на всех устройствах работает только PEAP+MSCHAPv2.
Отсюда требование хранить пароль в виде, из которого можно посчитать
NT-хеш, — и именно поэтому Kanidm держит RADIUS-пароли в открытом виде
([Kanidm RADIUS](https://kanidm.github.io/kanidm/stable/integrations/radius.html)).

### 5.4 Реализации

| Продукт | Версия | Особенность |
| --- | --- | --- |
| **FreeRADIUS** | 3.2.10 (2026-06-03) | эталон; модули LDAP, Kerberos, SQL, EAP, RadSec, CoA |
| **PacketFence** | 15.2.0 (2026-08-25) | NAC целиком: портал, регистрация, VLAN, compliance |
| **Authentik RADIUS outpost** | 2026.8.6 | только аутентификация, только PAP и EAP-TLS |
| **Kanidm radius** | 1.12.x | отдельный контейнер, креды из Kanidm, VLAN по группам |
| **Cisco ISE / Aruba ClearPass** | — | enterprise, закрытые |

**FreeRADIUS 4.0 не вышел.** На 2026-11-21 последний релизный тег —
`release_3_2_10`, ветка 4.x существует только в разработке
([tags](https://github.com/FreeRADIUS/freeradius-server/tags)). Это важно:
гайды «поставьте 4.0» преждевременны.

### 5.5 Что это значит для homelab

- **WiFi 802.1X** — единственный по-настоящему веский повод. Нужен AP с
  Enterprise-режимом (UniFi, OpenWrt/hostapd), RADIUS и сертификат для
  EAP-TLS либо PEAP+пароль.
- **VPN** — OpenVPN умеет `radiusplugin`; WireGuard не умеет ничего, кроме
  ключей. Для WireGuard RADIUS не нужен.
- **Проводной 802.1X** — редко: нужен управляемый коммутатор.
- **Учёт трафика** — accounting интересен, но в домашней сети обычно
  заменяется логами DHCP/DNS.

## 6. Как слои стыкуются

### 6.1 Эталонные связки

| Стек | Каталог | Билеты | Сеть | Веб-SSO |
| --- | --- | --- | --- | --- |
| **AD** | AD LDAP | AD KDC | RADIUS/NPS | OIDC через Entra/ADFS |
| **FreeIPA** | 389 DS | MIT krb5 | — | OIDC через Keycloak |
| **Samba AD DC** | Samba LDAP | Samba KDC | — | OIDC через Keycloak |
| **Authentik** | своя БД | — | RADIUS outpost | OIDC/SAML |
| **Kanidm** | своя БД | — | RADIUS-контейнер | OIDC |
| **ZITADEL** | своя БД | — | — | OIDC/SAML |

### 6.2 Один источник правды

```
                    ┌──────────────────────┐
   браузер ────────▶│  IdP (ZITADEL)       │──OIDC──▶ приложения
                    │  учётки, MFA, сессии │
                    └──────────┬───────────┘
                               │ федерация / LDAP-коннектор
                    ┌──────────▼───────────┐
   NAS/Samba ──────▶│  Каталог (LDAP)      │◀── SSSD ── Linux-хосты
   WiFi ───────────▶│  люди, группы, POSIX │
                    └──────────┬───────────┘
                               │ keytab / KDC
                    ┌──────────▼───────────┐
   NFSv4/SMB ──────▶│  Kerberos (KDC)      │
                    └──────────────────────┘
```

Правило: **владелец учёток один**. Остальные — либо федерация (спросить у
владельца), либо фасад (отдать данные владельца в чужом протоколе).

### 6.3 Split-brain

Типичная ошибка: завести LDAP «для NAS» и продолжать заводить людей в
ZITADEL. Через месяц — два списка, разные пароли, разные группы, и никто не
помнит, где источник.

Почему это не чинится синхронизацией:

- **Хеши не переносимы.** bcrypt/argon2 из ZITADEL не станут SSHA в OpenLDAP;
  синхронизировать можно только plaintext (недопустимо) или через
  pass-through (сложно и хрупко).
- **Схемы разные.** `posixAccount` и OIDC-claims не отображаются один в один.
- **Группы разные.** OIDC-группы — это claims, LDAP-группы — записи; маппинг
  всегда ручной.
- **Удаление не распространяется.** Отключил в IdP — в каталоге учётка жива.

Рабочие варианты: (а) каталог — владелец, IdP — федерация поверх него;
(б) IdP — владелец, LDAP — read-only фасад (Kanidm, Authentik outpost);
(в) один продукт закрывает всё (FreeIPA, Kanidm, Authentik).

### 6.4 Мосты OIDC↔LDAP

| Направление | Инструмент | Что делает |
| --- | --- | --- |
| LDAP → OIDC | Dex, Keycloak, ZITADEL, Authentik | IdP спрашивает каталог при входе |
| OIDC → LDAP | Authentik LDAP outpost, Kanidm LDAPS, lldap | отдаёт учётки IdP в LDAP-протоколе |
| Kerberos → OIDC | Keycloak (kerberos feature), oauth2-proxy (SPNEGO) | браузерный SSO через билет |

У каждого моста есть цена: задержка (flow на каждый bind), кеш
(устаревшие данные), ограниченная схема (не все атрибуты), отсутствие записи.

## 7. Ресурсы

Официальных цифр RSS у большинства проектов нет. Ниже — то, что заявлено
официально, и отдельно **оценка** по классу рантайма. Оценки не измерены и
служат только для сравнения порядка величин.

| Продукт | Рантайм | Официально | Оценка RSS | Диск | Зависимости |
| --- | --- | --- | --- | --- | --- |
| **OpenLDAP** | C, LMDB | нет | 15–60 МБ | БД + `maxsize` | нет |
| **389 DS** | C | нет | 100–300 МБ | БД + логи | нет |
| **FreeIPA** | Python + C + Java CA | нет | 1,5–3 ГБ (весь стек) | 10 ГБ+ | 389 DS, KDC, BIND, Dogtag |
| **Samba AD DC** | C | нет | 150–400 МБ | БД + sysvol | DNS |
| **Microsoft AD** | Windows | 2 ГБ RAM (минимум ОС) | 2 ГБ+ | 20 ГБ+ | Windows Server |
| **ApacheDS** | JVM | нет | 300–700 МБ | БД | JVM |
| **OpenDJ** | JVM | нет | 400 МБ–1 ГБ | БД | JVM |
| **Keycloak** | JVM (Quarkus) | лимит ≥ 750 МБ, рекомендуется 2 ГБ ([docs](https://www.keycloak.org/server/containers)) | 750 МБ–2 ГБ | — | Postgres |
| **Authentik** | Python + Go outpost | нет | 1–2 ГБ (server+worker) | — | Postgres, Redis |
| **ZITADEL** | Go | нет | 150–400 МБ | — | Postgres |
| **Kanidm** | Rust | нет | 50–150 МБ | — | нет |
| **lldap** | Rust | нет | 20–60 МБ | — | SQLite/MySQL/Postgres |
| **glauth** | Go | нет | 20–50 МБ | — | нет |
| **Dex** | Go | нет | 20–50 МБ | — | нет (или БД) |
| **FreeRADIUS** | C | нет | 30–100 МБ | — | LDAP/SQL по желанию |
| **PacketFence** | Perl + сервисы | 4 ядра, 8 ГБ, 100 ГБ ([download](https://packetfence.org/download.html)) | 8 ГБ+ | 100 ГБ+ | БД, веб-стек |

Что из этого следует:

- **JVM-продукты дороги не столько RSS, сколько лимитом и поведением GC.**
  Keycloak официально просит ставить memory limit, иначе heap растёт до 70 %
  памяти контейнера.
- **Полный IDM (FreeIPA, PacketFence) — это отдельная машина**, а не под
  рядом с приложениями.
- **Go/Rust-фасады дешевле всех**, но и умеют меньше: Kanidm/lldap/glauth не
  заменят каталог с произвольной схемой.

## 8. Что это значит для этого стенда

Сейчас в стенде есть ZITADEL (OIDC) и тестовый Authentik. Потребителей LDAP,
Kerberos и RADIUS нет: Samba-шара работает на локальных учётках, 802.1X в
стенде не заявлен, NFS не используется.

Поэтому решение — **не ставить ничего**. Это не «отказ от технологии», а
отсутствие задачи: каждый из трёх слоёв добавляет сервис, бэкап, мониторинг
и точку отказа.

Триггеры, при которых решение пересматривается:

| Триггер | Что понадобится | Кандидат |
| --- | --- | --- |
| SMB-шара с доменным входом, Windows-клиенты | AD-совместимость | Samba AD DC |
| Synology/TrueNAS + SSSD на узлах | LDAP + Kerberos | FreeIPA или 389 DS |
| Только «вход по LDAP» для пары сервисов | LDAP-фасад | Authentik outpost или lldap |
| WiFi 802.1X, гостевой портал | RADIUS | FreeRADIUS (+ LDAP/OIDC) |
| NFSv4 с `sec=krb5` | KDC | MIT krb5 или FreeIPA |
| Учебная цель «потрогать AD» | всё сразу | Samba AD DC в VM |

Отдельно: если появится LDAP, выбирать между «настоящим каталогом»
(OpenLDAP/389 DS/FreeIPA) и «фасадом» (Kanidm/Authentik/lldap) нужно по
наличию записи. Всё, что требует создавать учётки через LDAP, фасадом не
закрывается.

## 9. Учебный маршрут

Порядок — от простого к сложному, без внедрения в стенд:

1. **Протокол руками.** `ldapsearch -x -H ldap://… -b "" -s base` против
   любого демо-сервера: посмотреть Root DSE, `supportedControl`,
   `subschemaSubentry`. Затем — поиск с фильтром и paged results.
2. **OpenLDAP в контейнере.** Создать `ou=people`, пользователя, группу;
   проверить bind, `ldapwhoami`, смену пароля по RFC 3062, `ppolicy`.
3. **Схема.** Добавить свой objectClass с OID и убедиться, что без него
   `ldapadd` падает, а с ним — проходит.
4. **Репликация.** Поднять consumer с syncrepl, изменить запись на
   провайдере, посмотреть `contextCSN` и `entryCSN`.
5. **Kerberos.** Локальный KDC (MIT krb5 в контейнере или FreeIPA в VM):
   `kinit`, `klist`, keytab, `kvno`, затем SSH GSSAPI.
6. **RADIUS.** FreeRADIUS + `radtest`; затем `rlm_ldap` как бэкенд; затем
   EAP-TLS через hostapd в виртуалке (в основной сети не нужно).
7. **Фасады.** Тот же `ldapsearch` против Kanidm LDAPS и Authentik outpost:
   увидеть разницу в схеме, правах и отсутствии записи.

## 10. Не подтверждено

Честный список того, что в этой сессии не удалось проверить по первоисточнику:

| Утверждение | Почему не подтверждено |
| --- | --- |
| Samba AD DC: функциональные уровни до 2008 R2, ручная репликация sysvol | `wiki.samba.org` отдавал 429; в таблицах эти детали не используются |
| Authentik LDAP outpost не поддерживает запись | в документации провайдера описаны только bind и search; явного «read-only» нет |
| glauth не поддерживает запись | README описывает конфиг-бэкенд, но не заявляет ограничение явно |
| Точные RSS всех продуктов | измерений не было; в таблице это помечено как оценка |
| 389 DS: минимальные требования к памяти | официальной страницы не нашёл |
| Точный набор поддерживаемых LDAP-контролов в AD | требует [MS-ADTS](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/) и проверки на живом DC |
| FreeRADIUS 4.0: сроки | релиза нет, дат проект не публикует |

## Источники

**RFC и стандарты**

- LDAP: [4510](https://www.rfc-editor.org/rfc/rfc4510) (road map), [4511](https://www.rfc-editor.org/rfc/rfc4511) (протокол), [4512](https://www.rfc-editor.org/rfc/rfc4512) (модель), [4513](https://www.rfc-editor.org/rfc/rfc4513) (аутентификация), [4517](https://www.rfc-editor.org/rfc/rfc4517) (синтаксисы), [4519](https://www.rfc-editor.org/rfc/rfc4519) (схема), [2849](https://www.rfc-editor.org/rfc/rfc2849) (LDIF), [2307](https://www.rfc-editor.org/rfc/rfc2307) (NIS), [2798](https://www.rfc-editor.org/rfc/rfc2798) (inetOrgPerson), [4533](https://www.rfc-editor.org/rfc/rfc4533) (syncrepl), [2696](https://www.rfc-editor.org/rfc/rfc2696) (paged), [3062](https://www.rfc-editor.org/rfc/rfc3062) (password modify), [5805](https://www.rfc-editor.org/rfc/rfc5805) (transactions), [3673](https://www.rfc-editor.org/rfc/rfc3673) (operational)
- Kerberos: [4120](https://www.rfc-editor.org/rfc/rfc4120) (протокол), [4121](https://www.rfc-editor.org/rfc/rfc4121) (GSS-API), [3961](https://www.rfc-editor.org/rfc/rfc3961) (крипто), [3962](https://www.rfc-editor.org/rfc/rfc3962) (AES), [8009](https://www.rfc-editor.org/rfc/rfc8009) (AES-SHA2), [4757](https://www.rfc-editor.org/rfc/rfc4757) (RC4), [4178](https://www.rfc-editor.org/rfc/rfc4178) (SPNEGO), [6113](https://www.rfc-editor.org/rfc/rfc6113) (PKINIT), [6806](https://www.rfc-editor.org/rfc/rfc6806) (FAST), [6649](https://www.rfc-editor.org/rfc/rfc6649)/[8429](https://www.rfc-editor.org/rfc/rfc8429) (deprecation)
- RADIUS: [2865](https://www.rfc-editor.org/rfc/rfc2865), [2866](https://www.rfc-editor.org/rfc/rfc2866), [2868](https://www.rfc-editor.org/rfc/rfc2868), [2869](https://www.rfc-editor.org/rfc/rfc2869), [3579](https://www.rfc-editor.org/rfc/rfc3579), [5080](https://www.rfc-editor.org/rfc/rfc5080), [5176](https://www.rfc-editor.org/rfc/rfc5176), [6614](https://www.rfc-editor.org/rfc/rfc6614) (RadSec), [6929](https://www.rfc-editor.org/rfc/rfc6929), [8044](https://www.rfc-editor.org/rfc/rfc8044)
- EAP: [3748](https://www.rfc-editor.org/rfc/rfc3748), [5216](https://www.rfc-editor.org/rfc/rfc5216) (TLS), [5281](https://www.rfc-editor.org/rfc/rfc5281) (TTLS), [7170](https://www.rfc-editor.org/rfc/rfc7170) (TEAP), [9190](https://www.rfc-editor.org/rfc/rfc9190) (TLS 1.3), [2759](https://www.rfc-editor.org/rfc/rfc2759) (MSCHAPv2)

**Документация проектов**

- OpenLDAP: [Admin Guide 2.6](https://www.openldap.org/doc/admin26/), [replication](https://www.openldap.org/doc/admin26/replication.html), [backends](https://www.openldap.org/doc/admin26/backends.html), [download](https://www.openldap.org/software/download/)
- 389 DS: [port389.org](https://www.port389.org/), [releases](https://www.port389.org/docs/389ds/releases/release-notes.html)
- FreeIPA: [freeipa.org](https://www.freeipa.org/)
- Samba: [samba.org](https://www.samba.org/), [release history](https://www.samba.org/samba/history/)
- ApacheDS: [downloads](https://directory.apache.org/apacheds/downloads.html)
- Kanidm: [LDAP](https://kanidm.github.io/kanidm/stable/integrations/ldap.html), [RADIUS](https://kanidm.github.io/kanidm/stable/integrations/radius.html)
- Authentik: [LDAP provider](https://docs.goauthentik.io/add-secure-apps/providers/ldap/), [RADIUS provider](https://docs.goauthentik.io/add-secure-apps/providers/radius/)
- lldap: [README](https://github.com/lldap/lldap)
- Dex: [LDAP connector](https://dexidp.io/docs/connectors/ldap/)
- Keycloak: [container memory](https://www.keycloak.org/server/containers), [downloads](https://www.keycloak.org/downloads)
- ZITADEL: [LDAP IdP](https://zitadel.com/docs/guides/integrate/identity-providers/ldap)
- FreeRADIUS: [releases](https://github.com/FreeRADIUS/freeradius-server/releases), [tags](https://github.com/FreeRADIUS/freeradius-server/tags)
- PacketFence: [download](https://packetfence.org/download.html)
- MIT Kerberos: [distribution](https://web.mit.edu/kerberos/dist/index.html)
- Kubernetes authn: [docs](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
