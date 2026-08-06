# Uptime Kuma

Создать файл окружения и каталог данных:

```sh
cp .env.example .env
sudo install -d -m 0750 /storage/apps/uptime-kuma/data
docker compose up -d
```

Завершить первоначальную настройку учётной записи по адресу
`http://uptime.example.net/`. Добавить HTTP-мониторы маршрутов Traefik
и DNS-монитор, отправляющий запросы на `192.0.2.10`.

Сокет Docker намеренно не подключён. Мониторы HTTP, TCP, ping и DNS работают
без передачи Uptime Kuma контроля над Docker daemon.
