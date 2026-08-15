# code-server

`code-server` предоставляет VS Code-подобную IDE в браузере. Контейнер
доступен только через Traefik по адресу
`https://code.example.net/`; порт приложения напрямую на хост не
публикуется.

Образ закреплён на версии `4.132.0`. Постоянные данные находятся в
`/storage/apps/code-server`: настройки и расширения — в `home`, рабочие
проекты — в `workspace`. Каталог `/storage/apps` входит в общий Restic
snapshot.

## Запуск

Общий bootstrap создаёт `.env`, каталоги и проверяет Compose-конфигурацию:

```sh
bash scripts/bootstrap-platform.sh
cd code-server
docker compose config --quiet
docker compose up -d
docker compose ps
```

После первого запуска пароль можно получить так:

```sh
docker compose exec -T code-server sh -lc \
  'grep "^password:" /home/coder/.config/code-server/config.yaml'
```

Пароль следует сохранить в менеджере паролей. Внешняя аутентификация не
подключена: доступ защищён HTTPS Traefik и встроенной парольной авторизацией
code-server.

## Безопасность

- Не добавляйте `ports` в Compose: доступ должен идти через `traefiknet`.
- Не подключайте Docker socket без отдельной необходимости: это даёт IDE
  практически полный контроль над Docker-хостом.
- Рабочее пространство намеренно отделено от отслеживаемой копии
  `/home/artlab/projects/homelab`. Изменения самого homelab доставляются через
  локальный commit, push и серверный `git pull --ff-only`.
