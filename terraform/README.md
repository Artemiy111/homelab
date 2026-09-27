# Terraform

## Запуск

```sh cluster
# Создать токен
vault token create -policy=terraform -period=24h -orphan -display-name=terraform-macos
```

```sh macOS
# Залогиниться на macOS
export VAULT_ADDR="https://vault.<домен>"
vault login
```

```sh macOS
cd terraform/vault
terraform init
terraform plan
```
