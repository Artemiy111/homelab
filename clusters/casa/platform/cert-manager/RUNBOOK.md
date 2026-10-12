# cert-manager: эксплуатация

## Установка

```sh
# 1. Оператор и CRD
kubectl apply -f clusters/casa/platform/cert-manager/app.yaml
kubectl -n cert-manager get pods    # controller, webhook, cainjector

# 2. Webhook-солвер (нужны repo-creds и imagePullSecret, см. ниже)
kubectl apply -f clusters/casa/platform/dns01-webhook/app.yaml
kubectl -n cert-manager get pods    # dns01-webhook-...

# 3. Эмитенты и Certificate — из чарта (зоны, почта из values)
helm template clusters/casa/platform/homelab | kubectl apply -f -
```

## Секреты

Пакеты реестра Forgejo (образ и OCI-чарт) **публичные** — Argo и kubelet тянут их
анонимно, ни repo-creds, ни imagePullSecret не нужны.

Credentials DNS-провайдеров лежат в Vault и доставляются в кластер оператором
VSO через `VaultStaticSecret`. Единственная копия значения — Vault, в
репозитории секрета нет.

| Путь в Vault | Ключи | Destination Secret |
|---|---|---|
| `kv/dns01-webhook/dynv6` | `token` | `dns01-webhook-dynv6-token` |
| `kv/dns01-webhook/spaceship` | `api-key`, `api-secret` | `dns01-webhook-spaceship` |
| `kv/3x-ui/@dns01-webhook/egress` | `XUI_EGRESS_USERNAME`, `XUI_EGRESS_PASSWORD` | `dns01-webhook-egress` |

Имена ключей совпадают с ключами destination Secret'а в чарте webhook'а —
доставка не переименовывает ключи, поэтому при других именах правится
`clusters/casa/platform/cert-manager/vaultstaticsecret.yaml`, а не Vault.

## Доставка секретов и ротация

Применение и проверка доставки:

```sh
kubectl apply -f clusters/casa/platform/cert-manager/
kubectl -n cert-manager get vaultstaticsecret
kubectl -n cert-manager get secret dns01-webhook-dynv6-token dns01-webhook-spaceship
```

Секреты необязательны для пода: webhook поднимается без них, и падает только тот
challenge, у чьего провайдера нет credentials. Поэтому зона на dynv6 не мешает
зоне на Spaceship, и наоборот. Обратная сторона: ошибка в имени ключа выглядит
так же, как отсутствие секрета, — `SPACESHIP_API_KEY is not set` в логе webhook'а.
Отличаются они списком ключей в destination Secret'е.

**Credentials, доставленные после старта пода, в под не попадут.** Переменная
окружения читается один раз, при запуске контейнера, а `optional: true` не даёт
поду упасть. Поэтому после первого появления секрета в Vault под нужен
перезапуск, иначе webhook продолжит сообщать `SPACESHIP_API_KEY is not set` при
секрете, который на самом деле есть:

```sh
kubectl -n cert-manager annotate vaultstaticsecret dns01-webhook-spaceship \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
kubectl -n cert-manager rollout restart deploy/dns01-webhook-cert-manager-webhook-dns01
```

Тот же порядок применим к учётной записи прокси: `dns01-webhook-egress` доставляется
так же, но перезапуск нужен и для него.

Пароль обязан состоять из букв, цифр и `-`, `_`, `.`: символы `@`, `:`, `/`, `#`,
`%` и пробелы ломают разбор URL. Значение живёт в двух местах — в базе панели
3x-ui и в Vault, — поэтому ротация это два шага: сначала новая пара в панели,
затем Vault и форс-синк VSO. Подробности в `clusters/casa/apps/3x-ui/README.md`.

Ротация: обновить значение в Vault, дальше VSO перезапишет Secret за
`refreshAfter`. Форсировать без ожидания:

```sh
kubectl -n cert-manager annotate vaultstaticsecret dns01-webhook-spaceship \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
```

Проверка прав без вывода значений:

```sh
vault read kv/dns01-webhook/spaceship -format=json | jq -r '.data.data | keys'
```

## Порядок первого выпуска: staging → prod

1. Применить эмитенты и `Certificate` из чарта.
2. Для нового домена сначала указать в `certManager.certificates` парный
   staging-эмитент (`letsencrypt-staging-<зона>`), дождаться `Ready`. Так видно,
   что DNS-01 и webhook работают, не расходуя лимиты прода. Сертификат каждого
   домена лежит в своём Secret, поэтому подмена не заденет боевые.
3. Вернуть prod-эмитент, Secret перезапишется боевым сертификатом.

## Диагностика

```sh
kubectl -n traefik get certificate
kubectl -n traefik describe certificate wildcard          # Renewal Time
kubectl -n cert-manager get challenge,order,certificaterequest
kubectl -n cert-manager logs deploy/cert-manager --since=10m
kubectl -n cert-manager logs deploy/dns01-webhook --since=10m
```

Проверить CNAME-делегирование (только для зон dynv6):

```sh
dig +short _acme-challenge.<домен> CNAME
dig +short _acme-challenge.<домен> TXT
```