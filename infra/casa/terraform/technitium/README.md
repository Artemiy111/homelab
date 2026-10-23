# Technitium (Terraform)

DNS-записи зоны стенда и bootstrap-зоны `cloudflare-dns.com`. Развёртывание
самого сервера — `apps/casa/technitium/`, здесь только записи через HTTP API.
Значения — домен, адрес сервера и список делегирований — в `locals.tf`;
переменных у модуля нет.

## Запуск

```sh
read -rs TECHNITIUM_API_TOKEN
export TECHNITIUM_API_TOKEN

cd infra/casa/terraform/technitium
terraform init
terraform plan
```

## Доступ провайдера

Technitium рекомендует не выпускать токен для `admin`, а завести отдельного
пользователя. Готовится один раз в консоли:

1. **Administration → Users → Add** — пользователь `terraform`, с правом
   View/Modify на нужные зоны.
2. Меню пользователя (справа сверху) → **Create API Token** — имя `terraform`.
   Токен показывается **один раз**, сохранить его.
3. Значение — в Vault, рядом с админским паролем (`kv/technitium/secret`).

## Что управляется

| Ресурс | Запись |
| --- | --- |
| `technitium_record.apex` | `<домен>` A → сервер: wildcard apex не покрывает, а на него ссылается federation delegation Element (`m.server: <домен>:443`) |
| `technitium_record.wildcard` | `*.<домен>` A → сервер |
| `technitium_record.ts_wildcard` | `*.ts.<домен>` A → сервер: публичный вход через `yc` (`apps/yc/casa-edge`) дома и в tailnet ведёт напрямую, а не через облако |
| `technitium_record.dns` | `dns.<домен>` A → сервер |
| `technitium_record.zone_ns` | apex `NS` зоны → `dns.<домен>`: имя, которым зона объявляет себя авторитетной (см. ниже) |
| `technitium_record.cloudflare_bootstrap_*` | две A-записи зоны `cloudflare-dns.com` (обход DPI, см. `apps/casa/technitium/README.md`) |
| `technitium_record.delegation` | NS-записи делегированных подзон, по одной на сервер имён (см. ниже) |

Две bootstrap-записи живут в одном RRset, поэтому у них `overwrite = false` —
иначе вторая затирала бы первую.

## Имя сервера в зоне: NS и SOA

Зона объявляет себя авторитетной с каким-то именем сервера. Исторически там
осталось имя контейнера Docker-эпохи (`6ea60cf21452.`), которое не резолвится:
любой, кто спросит у Technitium `NS`/`SOA` зоны, получал мусор — на этом
спотыкался self-check cert-manager'а (`#1441`).

Правильное имя — `dns.<домен>`: внутри дома авторитетен именно Technitium, и это
имя резолвится в него же записью `technitium_record.dns`. Указывать на публичные
NS провайдера нельзя: тогда клиент пойдёт наружу за данными, которых там для
внутренних имён нет — зона split-horizon.

Что в Terraform, а что нет:

| Что | Чем | Почему |
| --- | --- | --- |
| apex `NS` | `technitium_record.zone_ns` | тип `NS` провайдер поддерживает, `overwrite = true` заменяет существующий RRset |
| `SOA` | руками, один раз | провайдер не умеет `SOA`: у `technitium_record` нет полей для `mname`/`rname`/таймингов, у `technitium_zone` — только `soa_serial` |
| `dnsServerDomain` | руками | в `technitium_server_settings` такого поля нет; влияет только на новые зоны |

Ручной шаг для `SOA` (консоль → Zones → `<домен>` → Records → `SOA`): primary
name server — `dns.<домен>.`, admin — `hostadmin.<домен>.`, тайминги не трогать,
serial Technitium поднимет сам. Значение хранится в зоне на PVC `technitium-etc`
(`/etc/dns/zones/`), поэтому переустановка пода его не сбрасывает.

Проверка:

```sh
dig +short @<адрес Technitium> NS <домен>      # dns.<домен>.
dig +short @<адрес Technitium> SOA <домен>     # dns.<домен>. hostadmin.<домен>. ...
dig +short @1.1.1.1 NS <домен>                 # публичное делегирование не изменилось
```

## Делегирование подзон

Technitium держит зону домена как split-horizon: публично домен делегирован
Spaceship, а Technitium отвечает только клиентам, которые им пользуются
(домашняя сеть, tailnet). Поэтому NS-записи здесь нужны ровно тогда, когда
подзона должна резолвиться изнутри дома так же, как снаружи; публичное
делегирование делается в авторитетной зоне у регистратора.

Список подзон и их NS-серверы лежат в `locals.tf`, рядом с доменом и адресом
сервера:

```hcl
delegations = {
  "yc.clusters" = ["ns1.yandexcloud.net", "ns2.yandexcloud.net"]
}
```

**Без точки на конце.** Technitium хранит NS-значение в `rData.nameServer` и
отдаёт его без завершающей точки; провайдер собирает id ресурса
(`<зона>::<имя>::NS::<значение>`) из этого значения. С точкой в конфиге id не
совпадает с тем, что отдаёт API: при `refresh` запись считается удалённой,
`plan` показывает создание, а `apply` падает с `record already exists`. Поэтому
и в `locals.tf`, и при ручном `terraform import` значение пишется без точки:

```sh
terraform import 'technitium_record.delegation["yc.clusters/ns1.yandexcloud.net"]' \
  'biplane.casa::yc.clusters.<домен>::NS::ns1.yandexcloud.net'
```

Имя подзоны может быть многоуровневым; промежуточная зона при этом не нужна.
Серверы имён для подзоны `yc.clusters.<домен>` берутся из вывода
`dns_delegation_ns` модуля `infra/yc/terraform/cluster`. Записи одного имени
живут в одном RRset, поэтому у них `overwrite = false`: с `true` вторая запись
затирала бы первую.

## Чего модуль не делает

- **Настройки сервера.** Forwarders, blocking, recursion — отдельный этап:
  `technitium_server_settings` — singleton и перезаписывает настройки целиком.
- **STIG-валидатор.** Не включается: для управления одними записями находки
  неинформативны, а `enabled = true` требует ещё блок `categorization`.
