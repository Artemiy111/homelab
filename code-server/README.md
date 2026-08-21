# code-server

`code-server` предоставляет VS Code-подобную IDE в браузере. Контейнер
доступен только через Traefik по адресу
`https://code.example.com/`; порт приложения напрямую на хост не
публикуется.

Образ закреплён на версии `4.132.0`. Постоянные данные находятся в
`$APPS_STORAGE_PATH/code-server`: настройки и расширения — в `home`, рабочие
проекты — в `workspace`. Каталог `$APPS_STORAGE_PATH` входит в общий Restic
snapshot.

## Запуск

Из каталога `code-server` выполнить:

```sh
bash ./init.sh
docker compose up -d
docker compose ps
```

`init.sh` создаёт `.env` (хост, UID/GID и имя пользователя) и каталоги `home`
и `workspace`.

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

## Почему нельзя просто снять привилегии

Контейнер уже запускается от не-root пользователя (`user:
"${CODE_SERVER_UID:-1000}:${CODE_SERVER_GID:-1000}"`). Попытка добавить
`security_opt: no-new-privileges:true` и `cap_drop: ALL` ломает запуск:
entrypoint образа использует `fixuid` (setuid-бинарь), чтобы переназначить
владельца `/home/coder` на заданный UID.

- При `no-new-privileges` повышение привилегий через setuid запрещено, `fixuid`
  падает и контейнер выходит с кодом 1.
- При `cap_drop: ALL` setuid-бинарь всё равно повышается до root, но с пустым
  набором capabilities (очищен bounding set), поэтому `fixuid` не может сделать
  `chown` и контейнер тоже падает.

Поэтому ограничиваемся только явным `user:` и не добавляем `no-new-privileges`/
`cap_drop`.
