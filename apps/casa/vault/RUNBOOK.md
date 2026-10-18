# HashiCorp Vault: эксплуатация

## Инициализация и unseal

Vault в standalone-режиме требует ручного запуска. Ни одно из этих значений не
должно попадать в git, в issue или в лог.

```sh
kubectl -n vault get pods
kubectl -n vault exec vault-0 -- vault operator init
```

Команда выдаёт unseal-ключи и root token. **Сохранить их вне репозитория.**
Для unseal нужны 3 ключа из 5:

```sh
kubectl -n vault exec -i vault-0 -- vault operator unseal <ключ>
# повторить трижды, затем:
kubectl -n vault exec -i vault-0 -- vault status
```

`vault status` ожидаемо отдаёт exit code 2, пока Vault `sealed`.

Вход в UI:

```sh
kubectl -n vault port-forward svc/vault 8200:8200
export VAULT_ADDR='http://127.0.0.1:8200'
```

UI также доступен на `https://vault.example.com` (TLS терминирует Traefik).

## Включение хранилища

```sh
vault secrets enable -path=kv kv-v2
```

## Вход

```sh
export VAULT_ADDR='http://127.0.0.1:8200'
vault login
```
