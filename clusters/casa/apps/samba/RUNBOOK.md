# Samba: эксплуатация

## Ротация пароля

Ротация: обновить значение в Vault, затем рестартнуть под.

## Проверка

Подняться и убедиться, что обе части на месте:

```sh
kubectl -n samba get pods
kubectl -n argocd get application samba
```

Шары видны клиенту:

```sh
smbclient -L //smb.example.com -U storage
```

Порт отвечает с клиента:

```sh
nc -z smb.example.com 445
```

Режим записи соответствует монтированию — в `ntfs2` запись отклоняется, в
`ntfs1` и `ntfs3` проходит:

```sh
smbclient //smb.example.com/ntfs2 -U storage -c 'put /etc/hostname .probe'
smbclient //smb.example.com/ntfs1 -U storage -c 'put /etc/hostname .probe'
smbclient //smb.example.com/ntfs3 -U storage -c 'put /etc/hostname .probe'
```

Режим задан в двух местах — `fstab` на хосте (как смонтирован том) и
`smb.conf`, `read only` (что разрешено клиенту). Они обязаны совпадать:
расхождение даёт отказ, который со стороны клиента читается как «том только
для чтения» при том, что смонтирован он на запись. Проверки на это больше
нет — при правке `fstab` сверяйтесь с секцией шары вручную.

### Проверка отсутствующего диска

Автоматической проверки нет, поэтому сценарий стоит прогнать вручную после
изменений в монтированиях. Под должен упасть при старте, а не раздать пустую
шару. Отмонтировать том и перезапустить под:

```sh
sudo umount /mnt/ntfs3
kubectl -n samba delete pod -l app=samba
kubectl -n samba get pods
```

Ожидается `Init:Error` — том не найден, `hostPath.type: Directory` не даёт
создать точку. Смонтировать обратно:

```sh
sudo mount /mnt/ntfs3
```

## Ручной вход

Внутрь пода:

```sh
kubectl -n samba exec deploy/samba -c smbd -- sh
```

Проверить эффективный конфиг — `testparm` проверяет синтаксис, но не
показывает, какие секции реально получились:

```sh
kubectl -n samba exec deploy/samba -c smbd -- testparm -s /etc/samba/smb.conf | grep '^\['
```

Должны быть `ntfs1`, `ntfs2`, `ntfs3`.
