# Homepage

Homepage — локальная стартовая страница для сервисов homelab.
URL: `https://home.example.com/`

## Запуск

`init.sh` формирует `config/settings.yaml`, затем проверяет
Compose-конфигурацию.

```sh
bash ./init.sh
docker compose up -d
docker compose ps
```
