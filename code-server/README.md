# code-server

Code-server предоставляет VS Code-подобную IDE в браузере.
URL: `https://code.example.com/`

## Запуск

Из каталога `code-server` выполнить:

```sh
bash ./init.sh
docker compose up -d
docker compose ps
```

После первого запуска пароль можно получить так:

```sh
docker compose exec -T code-server sh -lc \
  'grep "^password:" /home/coder/.config/code-server/config.yaml'
```

Пароль следует сохранить в менеджере паролей.

## Безопасность

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
