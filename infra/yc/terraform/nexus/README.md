# `nexus` (Terraform)

Managed Service for PostgreSQL для Nexus: два хоста в зонах `d` и `e`, база
`nexus`, роль `nexus`, пароль в Lockbox через Connection Manager, отдельный
сервисный аккаунт для чтения этого секрета.

## Что создаётся

| Ресурс | Что это |
| --- | --- |
| `yandex_mdb_postgresql_cluster.nexus` | PostgreSQL 18, пресет `s3-c2-m8` (2 CPU / 8 GiB), по 20 GB `network-ssd` на хост, автопереключение, бэкап в 22:00 UTC с хранением 7 дней |
| `yandex_mdb_postgresql_user.nexus` | роль `nexus`, `conn_limit = 50`, пароль генерирует Connection Manager |
| `yandex_mdb_postgresql_database.nexus` | база `nexus` с владельцем `nexus` и расширением `pg_trgm` |
| `yandex_vpc_security_group.postgres` | PostgreSQL принимает 6432 только из security group узлов кластера |
| `yandex_iam_service_account.lockbox` | `nexus-lockbox`, чтение пароля из Lockbox |
| `yandex_lockbox_secret_iam_member.nexus` | роль `lockbox.payloadViewer` на секрет, созданный Connection Manager |

Data source `yandex_connectionmanager_connection.nexus` только читает то, что
создал кластер: идентификатор подключения и секрета.

## Почему два хоста

Два хоста в разных зонах — минимум для автопереключения: отказ зоны `d` или `e`
оставляет один живой хост, и `autofailover` переводит его в primary. Квоты
`mdb.cpu.count` (4) и `mdb.memory.size` (16 GiB) покрывают ровно 2 × 2 CPU и
2 × 8 GiB; третий хост потребовал бы запроса квоты.

Хосты приватные (`assign_public_ip` не задан): кластер и Nexus живут в одной
сети VPC `k8s-vm`, публичный адрес базе не нужен. Из-за этого не работает
WebSQL в консоли — он ходит в базу снаружи.

## Почему пароль в Lockbox

`generate_password = true` — тот же путь, что галочка «сгенерировать пароль» в
консоли: пароль создаёт Connection Manager, в state Terraform он не попадает, а
хранится в секрете Lockbox. Секрет создаёт кластер, потому что в
`config.connection_manager.enabled = true`; выключить интеграцию нельзя, это
свойство API, а не настройка модуля.

Секрет содержит одну запись — `postgresql_password`. В кластер он приходит через
External Secrets Operator (`platform/yc/external-secrets/`), а не копируется
руками.

Чтобы дать ESO доступ, создаётся сервисный аккаунт `nexus-lockbox`; ключ для него
делается вручную и в Terraform не попадает:

```sh macOS
yc iam key create --service-account-name nexus-lockbox \
  --output /tmp/nexus-lockbox-key.json
kubectl -n external-secrets create secret generic yc-auth \
  --from-file=authorized-key=/tmp/nexus-lockbox-key.json
rm /tmp/nexus-lockbox-key.json
```

Ключ — секрет: его нельзя печатать, коммитить и оставлять в `~/Downloads`.
`yandex_iam_service_account_key` в конфигурации не используется именно поэтому:
приватный ключ оказался бы в state.

## Порядок применения

Модуль использует бэкенд из `state-backend/`, поэтому сначала должен быть
создан бакет и профиль `yc-tfstate` в `~/.aws/credentials`.

```sh macOS
cd infra/yc/terraform/nexus

export TF_CLI_CONFIG_FILE="$PWD/../.terraformrc"
export YC_TOKEN="$(yc iam create-token)"

unset YC_SERVICE_ACCOUNT_KEY_FILE
terraform init
terraform plan
terraform apply
```

Роли сервисного аккаунта `terraform` (`vpc`, `compute`, `load-balancer`, `dns`)
не покрывают Managed PostgreSQL, IAM и Lockbox, поэтому применяется IAM-токен
пользователя. Для регулярных прогонов сервисному аккаунту нужны `mdb.admin`,
`lockbox.admin` и `iam.serviceAccounts.admin` — это отдельное расширение прав,
а не часть модуля.

## Что читать после apply

```sh macOS
terraform output hosts          # FQDN обоих хостов для JDBC
terraform output lockbox_secret_id
terraform output connection_id
```

`hosts` и `lockbox_secret_id` попадают в манифесты юнита `apps/yc/nexus/`.
Пароль читать не нужно и нельзя: единственный потребитель — под Nexus, который
получает его из Lockbox через ESO.

## Ротация пароля

Connection Manager меняет пароль при обновлении подключения с новыми
`password_generation_options` (cookie). В Terraform это обновление не описано:
`generate_password` действует только при создании пользователя. Ротация —
отдельная операция:

```sh macOS
yc metadata-hub connection-manager connection update postgresql <connection-id> \
  --password-gen-opts cookie="$(date +%s)"
```

После неё ESO подтянет новую версию секрета, а под Nexus нужно перезапустить,
чтобы он перечитал `NEXUS_DATASTORE_NEXUS_PASSWORD`.
