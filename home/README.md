# Homepage

Homepage — локальная стартовая страница для сервисов homelab. Она доступна по
адресу `https://home.example.com/` через Traefik.

Контейнер намеренно не подключён к Docker socket: на странице используются
только декларативные ссылки из `config/services.yaml`, поэтому Homepage не
может читать или изменять состояние Docker daemon. Конфигурация монтируется
только для чтения, root filesystem контейнера также read-only.

## Запуск

На сервере выполните общий bootstrap, затем примените только этот проект:

```sh
cd /home/artlab/projects/homelab
bash scripts/bootstrap-platform.sh
cd home
docker compose config --quiet
docker compose up -d
docker compose ps
```

Изменения в `config/` отслеживаются Git. После изменения конфигурации можно
обновить страницу Homepage; для изменения `settings.yaml` при необходимости
перезапустите контейнер.
