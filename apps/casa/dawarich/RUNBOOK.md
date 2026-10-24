# Dawarich: эксплуатация

## Первый запуск

На пустой базе встроенный seed Dawarich создаёт администратора
`demo@dawarich.app` с паролем `safepassword`. Сразу после первого входа измените
email и пароль в настройках аккаунта.

## Проверка

```sh
curl --resolve dawarich.example.com:443:<node1-ip> \
  -fsS https://dawarich.example.com/api/v1/health
```

Health endpoint должен вернуть JSON со `"status":"ok"`.

После раскатки убедитесь, что поды действительно не под root и что метрики
собираются целиком:

```sh
kubectl -n dawarich exec deploy/dawarich -- id                 # uid=1000, не 0
kubectl -n dawarich exec deploy/dawarich-sidekiq -- id         # uid=1000, не 0
kubectl -n dawarich get pods                                    # все Running
```

```sh
curl --resolve dawarich.example.com:443:<node1-ip> -fsS \
  -u netdata:<пароль> https://dawarich.example.com/metrics | grep -c '^sidekiq_'
```

Счётчик больше нуля означает, что агрегатору доступен экспортёр Sidekiq. Если
метрик нет, в логе веба будет
`[AggregatingMetrics] sidekiq /metrics fetch failed` — смотреть Service
`dawarich-sidekiq` и политики сети.

## Владелец томов

Поды работают от uid 1000, и столько же владелец томов `storage` и `watched`.
Новые файлы создаются с этим uid, а группе доступ выдаёт `fsGroup`. Если файлы на
томе принадлежат другому uid — типичный случай после восстановления из backup —
загрузки и рендер постеров начнут падать с `Permission denied`. Вернуть владельца
можно одноразовым chown из пода, который умеет писать в том:

```sh
kubectl -n dawarich exec deploy/dawarich -- \
  chown -R 1000:1000 /var/app/storage /var/app/tmp/imports/watched
```

При обычном перезапуске это не требуется: `fsGroupChangePolicy: OnRootMismatch`
поправит права, если корень тома не совпадает с группой пода.

## Обновление

Перед обновлением создайте согласованный backup и прочитайте release notes.
