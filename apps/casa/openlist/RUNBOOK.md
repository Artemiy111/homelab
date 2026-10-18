# OpenList: эксплуатация

## Первый запуск

1. Argo синкает `openlist` и `samba` (второй — ради исключения в NetworkPolicy):

   ```sh
   kubectl -n argocd get application openlist samba
   ```

   Ожидаемо: `Synced` / `Healthy` у обоих.

2. Под поднимается и проходит пробы:

   ```sh
   kubectl -n openlist get pods
   ```

   Ожидаемо: `1/1 Running`, рестартов нет. `CrashLoopBackOff` с `permission
   denied` на `/opt/openlist/data` означает, что том не отдал запись
   пользователю 1001 — смотреть `securityContext` пода и класс тома.

3. Завести администратора: открыть `https://openlist.example.com` (маршрут закрыт
   forward auth — сначала вход через SSO). Первое открытие показывает **мастер
   установки**, а не форму входа: без `OPENLIST_ADMIN_PASSWORD` во вне dev-режима
   OpenList не создаёт администратора сам и ждёт его из веб-интерфейса. Пароль
   остаётся в SQLite на томе и в git не попадает.

## Подключение шары

В админке: **Сторы → Добавить → SMB**, поля драйвера:

| Поле | Значение |
| --- | --- |
| Адрес | `samba.samba.svc.cluster.local:445` |
| Имя пользователя | `storage` |
| Пароль | из Vault: `vault kv get kv/samba/storage`, поле `SMB_PASSWORD` |
| Имя шары | `ntfs1` |
| Корневая папка | `/` |

Пароль читать и вставлять руками, в терминал не печатать. Учётка общая с
остальными SMB-клиентами: сменивший пароль в Vault обязан помнить, что морда
после этого подключится только после повторного ввода.

Ожидаемо после сохранения: в «Файлах» открывается содержимое тома. Ошибка
драйвера вместо листинга — не настройка, а кандидат: драйвер SMB у апстрима
непроверенный (см. README), и это результат оценки, а не повод дочинивать его
здесь.

## Проверка на живом стенде

1. Морда жива:

   ```sh
   kubectl -n openlist exec deploy/openlist -- curl -s http://127.0.0.1:5244/ping
   ```

   Ожидаемо: `pong`.

2. Под достаёт до SMB — то есть исключение в NetworkPolicy `samba` доехало:

   ```sh
   kubectl -n openlist exec deploy/openlist -- sh -c \
     'curl -sv --connect-timeout 5 telnet://samba.samba.svc.cluster.local:445 2>&1 | grep -c "Connected to samba.samba.svc.cluster.local"'
   ```

   Ожидаемо: `1`. Ноль — смотреть `kubectl -n samba get networkpolicy
   allow-ingress -o yaml`, а не настройки хранилища.

3. Шара читается и пишется в обе стороны: листинг в морде совпадает с
   `smbclient //smb.example.com/ntfs1 -U storage` с клиента и с содержимым
   `/mnt/ntfs1` на узле; файл, созданный в морде, виден на шаре, и наоборот — без
   пересканирования.

4. Маршрут закрыт forward auth: анонимный запрос не отдаёт листинг, а редиректит
   на вход.

## Обновление образа

Тег semver, поэтому бамп — тег плюс дайджест:

```sh
docker buildx imagetools inspect openlistteam/openlist:v4.2.8-lite | grep Digest
```

Выбирать вариант `-lite`: остальные несут предустановленные aria2 и ffmpeg,
которые этой морде не нужны. Состояние и подключение переживают бамп, они на
томе.

## Диагностика

- **Шара пустая.** `hostPath` слеп к монтированиям хоста: на несмонтированной
  точке Samba раздаёт пустой каталог без единой ошибки в логах. Проверять
  монтирование на узле (`docs/agents/server-access.md`), а не под.
- **Под не ходит в Samba.** Правка нужна в юните `samba`
  (`allow-ingress` → `namespaceSelector` с `openlist`), а не здесь.
- **Форма входа просит пароль, которого нет.** Значит мастер установки уже
  пройден: администратор в базе есть. Сброс —
  `kubectl -n openlist exec deploy/openlist -- ./openlist admin set <новый>`;
  команда печатает пароль в stdout, поэтому вводить его в интерфейс и не
  оставлять в истории команд.

## Удаление юнита

```sh
rm -rf apps/casa/openlist
./scripts/argocd-units.sh > clusters/casa/argocd/kustomization.yaml
```

Затем убрать `namespaceSelector` с `openlist` из
`apps/casa/samba/manifests/networkpolicy.yaml` и перегенерировать
`docs/status/`. Том Longhorn останется: `longhorn-retain` — удалять осознанно,
вместе с решением оставить или выбросить морду.
