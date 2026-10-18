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

Режим записи соответствует монтированию — на `ntfs1` запись проходит:

```sh
smbclient //smb.example.com/ntfs1 -U storage -c 'put /etc/hostname .probe'
```

Режим задан в двух местах — `fstab` на хосте (как смонтирован том) и
`smb.conf`, `read only` (что разрешено клиенту). Они обязаны совпадать:
расхождение даёт отказ, который со стороны клиента читается как «том только
для чтения» при том, что смонтирован он на запись. Проверки на это больше
нет — при правке `fstab` сверяйтесь с секцией шары вручную.

### Проверка отсутствующего диска

Автоматической проверки нет, поэтому сценарий стоит прогнать вручную после
изменений в монтированиях. Точку монтирования держит автомонтирование, и без
остановки его юнита `umount` вернёт занятую точку:

```sh
sudo systemctl stop mnt-ntfs1.automount
sudo umount /mnt/ntfs1
kubectl -n samba delete pod -l app=samba
kubectl -n samba get pods
```

Ожидается, что под поднимется, а шара `ntfs1` откроется **пустой**: проверки
монтирования в поде нет по построению (см. README). Смонтировать обратно:

```sh
sudo systemctl start mnt-ntfs1.automount
sudo mount /mnt/ntfs1
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

Должна быть `ntfs1`.
