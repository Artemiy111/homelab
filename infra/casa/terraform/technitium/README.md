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
| `technitium_record.cloudflare_bootstrap_*` | две A-записи зоны `cloudflare-dns.com` (обход DPI, см. `apps/casa/technitium/README.md`) |

Делегирования подзон в Terraform нет — причина ниже.

Две bootstrap-записи живут в одном RRset, поэтому у них `overwrite = false` —
иначе вторая затирала бы первую.

## Делегирование подзон

Technitium держит зону домена как split-horizon: публично домен делегирован
Spaceship, а Technitium отвечает только клиентам, которые им пользуются
(домашняя сеть, tailnet). NS-записи подзоны нужны ровно тогда, когда она должна
резолвиться изнутри дома так же, как снаружи; публичное делегирование делается в
авторитетной зоне у регистратора.

**Terraform этих записей не ведёт.** Провайдер `darkhonor/technitium` не умеет
читать NS: в ответе API значение лежит в `rData.nameServer`, а провайдер ищет
`rData.value`, получает `null` и считает запись удалённой. Дальше `apply` падает
с `Cannot add record: record already exists`, а `terraform import` — с
`Cannot import non-existent remote object`: импорт вызывает то же чтение.

Поэтому делегирование подзоны заводится в консоли Technitium руками, один раз на
подзону. Для `yc.clusters.<домен>` серверы имён берутся из вывода
`dns_delegation_ns` модуля `infra/yc/terraform/cluster`:

```sh
cd infra/yc/terraform/cluster && terraform output dns_delegation_ns
```

Записи одного имени живут в одном RRset, поэтому добавлять их надо обе, и
повторное добавление того же имени затрёт предыдущее значение.

Проверка:

```sh
dig +short @<адрес Technitium> NS yc.clusters.<домен>
```

## Чего модуль не делает

- **Настройки сервера.** Forwarders, blocking, recursion — отдельный этап:
  `technitium_server_settings` — singleton и перезаписывает настройки целиком.
- **STIG-валидатор.** Не включается: для управления одними записями находки
  неинформативны, а `enabled = true` требует ещё блок `categorization`.
