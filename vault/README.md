# HashiCorp Vault — secrets management

Полнофункциональный vault для хранения секретов, динамических учётных
данных, шифрования (transit) и PKI. Open-source版 — BSL 1.1.

## Архитектура

- **Vault** — сервер с UI и API (порт 8200)
- **Хранилище** — файловый бэкенд (`/storage/apps/vault/data`)
- **IPC_LOCK** — защита от swap (обязательно)

## Запуск

```sh
docker compose up -d
```

### Инициализация (первый запуск)

```sh
docker exec -it vault vault operator init
```

Сохранить unseal-ключи и root token. Затем unseal (3 из 5 ключей):

```sh
docker exec -it vault vault operator unseal <KEY_1>
docker exec -it vault vault operator unseal <KEY_2>
docker exec -it vault vault operator unseal <KEY_3>
```

### Вход

```sh
export VAULT_ADDR='http://127.0.0.1:8200'
vault login <ROOT_TOKEN>
```

### Первый секрет

```sh
vault secrets enable -path=kv kv-v2
vault kv put kv/myapp db_password=s3cret api_key=abc123
vault kv get kv/myapp
```

## Dev mode (для быстрого тестирования)

```sh
docker compose -f compose.dev.yaml up -d
```

Dev mode: in-memory, auto-unseal, root token = `dev-root-token`.
Все данные теряются при перезапуске.

## Web UI

Открыть `https://vault.example.net` → войти с root token.

## Важно

- Unseal-ключи и root token хранить **отдельно** от сервера.
- При перезапуске контейнера Vault снова sealed → нужно unseal заново.
- Для автозапуска нужен auto-unseal (KMS) или Vault Agent.
