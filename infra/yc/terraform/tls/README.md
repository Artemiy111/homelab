# `tls` (Terraform)

Wildcard-сертификат Let's Encrypt на `*.yc.clusters.biplane.casa` в Yandex
Certificate Manager. Выпуск — DNS-01: подтверждение кладётся CNAME-записью в
зону `yc`, которой владеет модуль `cluster/`.

## Зачем

Для `biplane.casa` у клиентов уже есть HSTS с `includeSubDomains`, поэтому
браузер не откроет приложение `yc` по HTTP: он молча заменит схему на HTTPS.
Сертификат на подзону — единственный способ пустить пользователей в приложения
без предупреждений. Wildcard выбран, чтобы новое приложение не требовало нового
сертификата и новой записи.

## Что создаётся

| Ресурс | Что это |
| --- | --- |
| `yandex_cm_certificate.yc_wildcard` | managed-сертификат `*.yc.clusters.biplane.casa`, challenge `DNS_CNAME` |
| `yandex_dns_recordset.challenge` | CNAME `_acme-challenge.yc.clusters.biplane.casa`, значение приходит от Certificate Manager |

Зона читается data source'ом по имени `yc`: владелец зоны — модуль `cluster/`,
дублировать её здесь нельзя.

## Порядок применения

Провайдеру нужен доступ к Certificate Manager и Cloud DNS. Роли сервисного
аккаунта `terraform` (`vpc`, `compute`, `load-balancer`, `dns`) этого не
покрывают, поэтому первый выпуск — IAM-токеном пользователя:

```sh macOS
cd infra/yc/terraform/tls

export TF_CLI_CONFIG_FILE="$PWD/../.terraformrc"
export YC_TOKEN="$(yc iam create-token)"

unset YC_SERVICE_ACCOUNT_KEY_FILE
terraform init
terraform apply
```

Для регулярных прогонов сервисному аккаунту нужен `certificate-manager.admin`
в дополнение к `dns.editor` — это расширение прав, а не часть модуля.

Выпуск не мгновенный: `apply` возвращается, когда Certificate Manager выдал
challenge, дальше Let's Encrypt проверяет CNAME. Статус:

```sh macOS
yc certificate-manager certificate get --name yc-wildcard --format json | jq -r '.status'
```

`VALIDATING` → `ISSUED` обычно за несколько минут. Пока стоит `VALIDATING`,
`terraform plan` покажет расхождение в `status` — это ожидаемо.

## Содержимое сертификата

Cert Manager хранит сертификат и продлевает его сам, но в Kubernetes их нужно
положить отдельно. В репозиторий ключ не попадает:

```sh macOS
yc certificate-manager certificate content --name yc-wildcard \
  --chain /tmp/yc-wildcard.crt --key /tmp/yc-wildcard.key > /dev/null

kubectl -n envoy-gateway-system create secret tls yc-wildcard-tls \
  --cert=/tmp/yc-wildcard.crt --key=/tmp/yc-wildcard.key

rm /tmp/yc-wildcard.crt /tmp/yc-wildcard.key
```

`> /dev/null` обязателен: без него `yc` печатает содержимое сертификата и
приватный ключ в терминал, то есть ключ попадает в scrollback и логи оболочки.

Секрет — `kubernetes.io/tls` с ключами `tls.crt` и `tls.key`: именно в таком
виде его ждёт `certificateRefs` у Gateway.

## Продление

Certificate Manager продлевает managed-сертификат автоматически и требует,
чтобы challenge-CNAME оставался в зоне — поэтому запись создаётся Terraform и не
удаляется. Kubernetes Secret сам не обновится: синхронизацию содержимого в
Secret нужно делать отдельно (CronJob или ESO), иначе через 90 дней Gateway
продолжит отдавать старый сертификат, пока его не заменят руками.

## Чего здесь не делать

- **Не переносить зону сюда.** Два владельца одной зоны Terraform не прощает:
  второй `apply` удалит записи первого.
- **Не удалять challenge-запись после выпуска.** Она нужна при продлении.
- **Не хранить `tls.key` в репозитории или в state.** Секрет создаётся в
  кластере из файла, который сразу удаляется.
