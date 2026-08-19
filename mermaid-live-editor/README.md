# Mermaid Live Editor

Редактор Mermaid-диаграмм в браузере. Доступен через Traefik по адресу
`https://mermaid.example.com/`; порт приложения на хосте не публикуется.

## Запуск

```sh
bash init.sh        # создаёт .env (MERMAID_HOST из общего DOMAIN)
docker compose up -d
```
