# Filestash: эксплуатация

## Первый запуск

1. Argo синкает `filestash` и `samba` (второй — ради исключения в NetworkPolicy):

   ```sh
   kubectl -n argocd get application filestash samba
   ```

   Ожидаемо: `Synced` / `Healthy` у обоих.

2. Под поднимается и проходит пробы:

   ```sh
   kubectl -n filestash get pods
   ```

   Ожидаемо: `1/1 Running`, рестартов нет. `CrashLoopBackOff` с `permission
   denied` на `/app/data` означает, что том не отдал запись пользователю 1000 —
   смотреть `securityContext` пода и класс тома.

3. Завести администратора: открыть `https://filestash.example.com/admin/setup`
   (маршрут закрыт forward auth — сначала вход через SSO) и задать пароль
   администратора. Пароль в git не попадает и в Vault не пишется: он остаётся в
   SQLite на томе.

## Подключение шары

Один раз, в веб-интерфейсе: **Connections → Samba**, поля:

| Поле | Значение |
| --- | --- |
| Host | `samba.samba.svc.cluster.local` |
| Port | `445` |
| Share | `ntfs1` |
| Username | `storage` |
| Password | из Vault: `vault kv get kv/samba/storage`, поле `SMB_PASSWORD` |

Пароль читать и вставлять руками, в терминал не печатать. Учётка общая с
остальными SMB-клиентами: сменивший пароль в Vault обязан помнить, что морда
после этого подключится только после повторного ввода, а до тех пор покажет
ошибку входа.

Ожидаемо после сохранения: листинг корня `ntfs1` открывается, файлы
скачиваются.

## Проверка на живом стенде

1. Морда жива:

   ```sh
   kubectl -n filestash exec deploy/filestash -- curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8334/healthz
   ```

   Ожидаемо: `200`.

2. Под достаёт до SMB — то есть исключение в NetworkPolicy `samba` доехало:

   ```sh
   kubectl -n filestash exec deploy/filestash -- curl -s --connect-timeout 5 telnet://samba.samba.svc.cluster.local:445; echo "код: $?"
   ```

   Ожидаемо: `код: 0`. Код `7` (не удалось подключиться) — почти всегда
   NetworkPolicy, а не Samba: смотреть `kubectl -n samba get networkpolicy
   allow-ingress -o yaml`.

3. Шара читается и пишется в обе стороны: листинг в морде совпадает с
   `smbclient //smb.example.com/ntfs1 -U storage` с клиента и с содержимым
   `/mnt/ntfs1` на узле; файл, созданный в морде, виден на шаре, и наоборот —
   без пересканирования.

4. Осмысленно приложить пару скриншотов листинга и сохранённого подключения к
   итогу оценки в issue: сравнивать два кандидата придётся по ним.

5. Маршрут закрыт forward auth: анонимный запрос не отдаёт листинг, а
   редиректит на вход.

## Обновление образа

У `machines/filestash` нет semver-тегов: тег и есть дайджест сборки. Бамп — это
подмена дайджеста в `image`. Состояние и подключение переживают бамп, они на
томе, поэтому проверка после бампа — что морда открывается и шара читается.

```sh
docker buildx imagetools inspect machines/filestash:latest | grep Digest
```

## Диагностика

- **Шара пустая.** `hostPath` слеп к монтированиям хоста: на несмонтированной
  точке Samba раздаёт пустой каталог без единой ошибки в логах. Проверять
  монтирование на узле (`docs/agents/server-access.md`), а не под.
- **Под не ходит в Samba.** Правка нужна в юните `samba`
  (`allow-ingress` → `namespaceSelector` с `filestash`), а не здесь: сама морда
  про NetworkPolicy не знает и показывает только ошибку входа.
- **Ничего не помнит после перезапуска.** Состояние живёт в SQLite на томе;
  проверить `kubectl -n filestash get pvc filestash-data` — `Bound`, и что под
  смонтировал именно его.

## Удаление юнита

```sh
rm -rf clusters/casa/apps/filestash
./scripts/argocd-units.sh > clusters/casa/kustomization.yaml
```

Затем убрать `namespaceSelector` с `filestash` из
`clusters/casa/apps/samba/manifests/networkpolicy.yaml` и перегенерировать
`docs/status/`. Том Longhorn останется: `longhorn-retain` — удалять осознанно,
вместе с решением оставить или выбросить морду.
