# Forgejo

Forgejo — лёгкая self-hosted Git-платформа (форк Gitea, лицензия GPL-3.0+,
управление Codeberg e.V.). Веб-интерфейс доступен через Traefik по адресу
`https://forgejo.example.net/`, Git over SSH — на порту `2223`.
PostgreSQL и HTTP-порт контейнера на хост не публикуются.

Самостоятельная регистрация отключена после первоначальной настройки, новые
репозитории и профили приватны по умолчанию. Forgejo Actions отключены до
появления отдельного runner.

## Первый запуск

Общий bootstrap создаёт каталоги данных и `.env`, генерирует пароль PostgreSQL
и сохраняет его на сервере с правами `0600`:

```sh
cd /home/artlab/projects/homelab
bash scripts/bootstrap-platform.sh
cd forgejo
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

Откройте `https://forgejo.example.net/` — откроется мастер установки.
Укажите адрес PostgreSQL (`db:5432`), имя базы и пароль из `.env`, создайте
первого пользователя (он автоматически станет администратором).

Пароль PostgreSQL можно посмотреть на сервере:

```sh
sed -n '/^POSTGRES_PASSWORD=/p' .env
```

После завершения установки отключите регистрацию и веб-мастер, добавив в
`compose.yaml` в секцию `x-forgejo-environment`:

```yaml
  FORGEJO__security__INSTALL_LOCK: "true"
  FORGEJO__service__DISABLE_REGISTRATION: "true"
```

Затем перезапустите контейнер:

```sh
docker compose up -d
```

Чтобы SSH был доступен клиентам, разрешите порт `2223` в активной зоне
firewalld (команда требует root):

```sh
sudo firewall-cmd --permanent --add-port=2223/tcp
sudo firewall-cmd --reload
```

Порт привязан только к LAN-адресу `192.0.2.10`; на роутере его публиковать не
нужно. Удалённые клиенты приходят к этому адресу через Tailscale subnet route.

## Использование

После добавления публичного SSH-ключа в настройках профиля репозиторий можно
клонировать так:

```sh
git clone ssh://git@forgejo.example.net:2223/OWNER/REPOSITORY.git
```

При создании дополнительных пользователей используйте административную панель.
SMTP намеренно не настроен: восстановление пароля по почте не заработает, пока
не будет выбран и настроен почтовый провайдер.

## Проверка

```sh
docker compose ps
docker compose exec --user git app forgejo doctor check --all
curl --resolve forgejo.example.net:443:192.0.2.10 \
  -fsS https://forgejo.example.net/api/healthz
ssh -T -p 2223 git@192.0.2.10
```

Health endpoint должен вернуть JSON со `"status":"pass"`. Первая SSH-проверка
может завершиться сообщением о невозможности shell-доступа — для Forgejo это
нормально, если пользователь распознан.

## Резервное копирование

Forgejo меняет базу и Git-репозитории независимо, поэтому для согласованного снимка
на время дампа и Restic backup приложение нужно остановить:

```sh
cd /home/artlab/projects/homelab/forgejo
docker compose stop app
docker compose --profile tools run --rm backup-db
cd ../restic
docker compose run --rm backup
cd ../forgejo
docker compose start app
```

Дамп PostgreSQL сохраняется в `/storage/apps/forgejo/backups/forgejo.dump`, а
репозитории, LFS-объекты, вложения, конфигурация и SSH-ключи — в
`/storage/apps/forgejo/data`. Оба каталога входят в общий Restic snapshot. Локальный
Restic repository находится на том же физическом диске и не защищает от его
поломки или потери.

## Обновление

Перед обновлением создайте согласованный backup. Затем измените фиксированный тег
Forgejo в `compose.yaml`, проверьте release notes и выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
docker compose exec --user git app forgejo doctor check --all
```
