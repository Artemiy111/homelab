# Gitea

Gitea предоставляет приватный Git-сервис в локальной сети и через Tailscale.
Веб-интерфейс доступен через Traefik по адресу
`https://gitea.example.net/`, а Git over SSH — на порту `2222` того же
адреса. PostgreSQL и HTTP-порт контейнера на хост не публикуются.

Самостоятельная регистрация и OpenID отключены, новые репозитории и профили
приватны по умолчанию. Gitea Actions отключены до появления отдельного runner с
ограниченными правами.

## Первый запуск

Общий bootstrap создаёт каталоги данных и `.env`, генерирует независимые пароли
PostgreSQL и администратора и сохраняет их только на сервере с правами `0600`:

```sh
cd /home/artlab/projects/homelab
bash scripts/bootstrap-platform.sh
cd gitea
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose --profile tools run --rm init-admin
docker compose ps
```

`init-admin` нужно выполнить только один раз. При первом входе Gitea потребует
сменить сгенерированный пароль. Исходные реквизиты можно увидеть только в
терминале сервера:

```sh
sed -n '/^GITEA_ADMIN_\(USERNAME\|PASSWORD\)=/p' .env
```

Чтобы SSH был доступен клиентам, разрешите выбранный порт в активной зоне
firewalld (команда требует root):

```sh
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --reload
```

Порт привязан только к LAN-адресу `192.0.2.10`; на роутере его публиковать не
нужно. Удалённые клиенты приходят к этому адресу через Tailscale subnet route.

## Использование

После добавления публичного SSH-ключа в настройках профиля репозиторий можно
клонировать так:

```sh
git clone ssh://git@gitea.example.net:2222/OWNER/REPOSITORY.git
```

При создании дополнительных пользователей используйте административную панель.
SMTP намеренно не настроен: восстановление пароля по почте не заработает, пока
не будет выбран и настроен почтовый провайдер.

## Проверка

```sh
docker compose ps
docker compose exec --user git app gitea doctor check --all
curl --resolve gitea.example.net:443:192.0.2.10 \
  -fsS https://gitea.example.net/api/healthz
ssh -T -p 2222 git@192.0.2.10
```

Health endpoint должен вернуть JSON со `"status":"pass"`. Первая SSH-проверка
может завершиться сообщением о невозможности shell-доступа — для Gitea это
нормально, если пользователь распознан.

## Резервное копирование

Gitea меняет базу и Git-репозитории независимо, поэтому для согласованного снимка
на время дампа и Restic backup приложение нужно остановить:

```sh
cd /home/artlab/projects/homelab/gitea
docker compose stop app
docker compose --profile tools run --rm backup-db
cd ../restic
docker compose run --rm backup
cd ../gitea
docker compose start app
```

Дамп PostgreSQL сохраняется в `/storage/apps/gitea/backups/gitea.dump`, а
репозитории, LFS-объекты, вложения, конфигурация и SSH-ключи — в
`/storage/apps/gitea/data`. Оба каталога входят в общий Restic snapshot. Локальный
Restic repository находится на том же физическом диске и не защищает от его
поломки или потери.

## Обновление

Перед обновлением создайте согласованный backup. Затем измените фиксированный тег
Gitea в `compose.yaml`, проверьте release notes и выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
docker compose exec --user git app gitea doctor check --all
```
