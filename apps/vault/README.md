# HashiCorp Vault — secrets management

Полнофункциональный vault для хранения секретов, динамических учётных
данных, шифрования (transit) и PKI. Open-source版 — BSL 1.1.

Разворачивается манифестами в `apps/vault/k8s/`.

## Архитектура

- **Vault** — сервер с UI и API (порт 8200)
- **Хранилище** — встроенный Raft-бэкенд (`/storage/apps/vault/data`)
- **Отключён mlock** — для Raft это рекомендуемая настройка; swap на хосте
  должен оставаться отключённым.

## Инициализация (первый запуск)

Сохранить unseal-ключи и root token. Для разблокировки нужно 3 из 5 ключей.

## Вход

```sh
export VAULT_ADDR='http://127.0.0.1:8200'
vault login <ROOT_TOKEN>
```

## Первый секрет

```sh
vault secrets enable -path=kv kv-v2
vault kv put kv/myapp db_password=s3cret api_key=abc123
vault kv get kv/myapp
```

## Web UI

Открыть `https://vault.example.com` → войти с root token.

## Важно

- Unseal-ключи и root token хранить **отдельно** от сервера.
- API доступен извне только через Traefik по HTTPS; порт `8200` доступен
  только внутри кластера.
- При перезапуске контейнера Vault снова sealed → нужно unseal заново.
- Для автозапуска нужен auto-unseal (KMS) или Vault Agent.
