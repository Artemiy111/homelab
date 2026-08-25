# Forgejo

Forgejo — лёгкая self-hosted Git-платформа (форк Gitea).
URL: `https://forgejo.example.com/`
Git over SSH: `2222:`.

Самостоятельная регистрация отключена после первоначальной настройки, новые
репозитории и профили приватны по умолчанию. Forgejo Actions отключены до
появления отдельного runner.

## Первый запуск

Из корня репозитория:

```sh
bash scripts/bootstrap-platform.sh forgejo
```
> Любые последующие команды `docker compose` этого сервиса требуют того же окружения:
> выполняйте их через `bash scripts/compose-secrets.sh forgejo …` или повторным
> `bash scripts/bootstrap-platform.sh forgejo`.


Откройте `https://forgejo.example.com/` — откроется мастер установки.
Укажите адрес PostgreSQL (`db:5432`), имя базы и пароль, создайте
первого пользователя (он автоматически станет администратором).

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

Чтобы SSH был доступен клиентам, разрешите порт `2232` в активной зоне
firewalld (команда требует root):

```sh
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --reload
```

Порт привязан только к LAN-адресу; на роутере его публиковать не
нужно. Удалённые клиенты приходят к этому адресу через Tailscale subnet route.

## Использование

После добавления публичного SSH-ключа в настройках профиля репозиторий можно
клонировать так:

```sh
git clone ssh://git@forgejo.example.com:2222/OWNER/REPOSITORY.git
```

При создании дополнительных пользователей используйте административную панель.
SMTP намеренно не настроен: восстановление пароля по почте не заработает, пока
не будет выбран и настроен почтовый провайдер.

## Проверка

```sh
docker compose ps
docker compose exec --user git app forgejo doctor check --all
curl --resolve forgejo.example.com:443:192.0.2.10 \
  -fsS https://forgejo.example.com/api/healthz
ssh -T -p 2222 git@192.0.2.10
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

Дамп PostgreSQL сохраняется в `$APPS_STORAGE_PATH/forgejo/backups/forgejo.dump`, а
репозитории, LFS-объекты, вложения, конфигурация и SSH-ключи — в
`$APPS_STORAGE_PATH/forgejo/data`. Оба каталога входят в общий Restic snapshot. Локальный
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
