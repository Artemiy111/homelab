# Расширение дискового пространства homelab за счёт диска ноутбука: сетевые ФС и блочные решения

Дата проверки: 2026-08-16.

## Вывод

Для сценария «прозрачно добавить диск ноутбука как ещё одну локальную ФС»
для файловых сервисов homelab (Jellyfin, Nextcloud, Immich и т. п.) оптимально:

- **NFSv4** — NFS-сервер (`nfs-utils`, `nfs-server.service`) на ноутбуке Fedora,
  встроенный клиент ядра на homelab-хосте, монтирование через `/etc/fstab`
  и проброс в контейнеры bind-mount'ом (или `docker volume` с драйвером
  `local` и опциями `type=nfs`).
- **iSCSI** — единственное «честное» блочное решение (homelab увидит `/dev/sdX`
  и сможет наложить LVM/свою ФС), но требует на порядок больше осторожности:
  ФС поверх iSCSI-устройства надо чисто открывать/закрывать, сон ноутбука
  превращается в ошибки ФС на homelab. Вариант оправдан только если реально
  нужен именно блочный диск (образы ВМ, свой LVM), а не файловая точка
  монтирования.
- SMB/CIFS — разумная альтернатива, если понадобятся Windows/macOS-клиенты или
  встроенное шифрование SMB3; но для пары Linux↔Linux это userspace-демон
  на сервере вместо ядерного `nfsd`.
- Ceph, GlusterFS и DRBD для этой задачи отвергнуты: это кластерные/HA-
  технологии для другого назначения (распределённый кластер, зеркало HA),
  тяжёлые и требующие постоянного аптайма всех узлов.

Важная оговорка: при любом варианте данные физически лежат только на ноутбуке —
это не бэкап; ноутбук должен быть включён и не уходить в сон.

## Сравнительная таблица

| Решение | Web-UI | RAM (сервер / клиент) | Пропускная способность / накладные | Назначение (официальное) | Прозрачность | Развёртывание (Fedora + Docker/модули) |
|---|---|---|---|---|---|---|
| NFSv3/v4 | нет | сервер и клиент — в ядре; userspace только вспомогательные демоны; офиц. цифр нет | ядро-ядро, стриминг близко к линейной скорости LAN; накладные — RPC/XDR + сетевой стек; офиц. бенчмарков нет | файловый обмен по LAN ([nfs(5)](https://man7.org/linux/man-pages/man5/nfs.5.html)) | точка монтирования ФС (kernel), fstab/automount | пакет `nfs-utils` в Fedora; Docker — bind-mount или `type=nfs` volume |
| SMB/CIFS (Samba) | нет (в современных версиях SWAT отсутствует) | `smbd` — userspace, процесс на сессию; офиц. цифр нет | клиент в ядре (`cifs`), сервер userspace; SMB3 multichannel; цифр нет | интероперабельность с Windows/macOS ([smbd(8)](https://www.samba.org/samba/docs/man/manpages-3/smbd.8.html)) | точка монтирования ФС (kernel cifs) | пакет `samba` в Fedora; в контейнере работает, но нужен проброс портов/привилегии |
| SSHFS | нет | один FUSE-процесс на монтирование; офиц. цифр нет | FUSE + SSH/SFTP; высокие накладные на операцию (FUSE + SFTP, без серверного data-path); цифр нет | «клиент сетевой ФС для подключения к SSH-серверам», ad-hoc ([README](https://github.com/libfuse/sshfs)) | FUSE-монтирование (не в ядре) | пакет `fuse-sshfs` в Fedora; сервер — просто sshd |
| iSCSI (LIO + open-iscsi) | нет (targetcli — CLI) | LIO и initiator — в ядре; iscsid/targetcli малы; офиц. цифр нет | блочная семантика, оба конца в ядре, низкие накладные; цифр нет | блочный доступ по TCP/IP ([RFC 7143](https://www.rfc-editor.org/rfc/rfc7143)) | блочное устройство `/dev/sdX` → можно LVM/любая ФС | LIO в ядре Fedora, пакет `targetcli`; клиент `open-iscsi` (модули `iscsi_tcp`, `libiscsi`); Docker — только через монтирование на хосте |
| CephFS / RBD | да — Ceph Dashboard (встроен в ceph-mgr) | 512 МБ–1 ГБ на демон (мин.), 1–2 ГБ (реком.), офиц. | масштабируется кластером; для 1–2 узлов избыточно; бенчмарки только для кластеров | распределённый object store; CephFS и RBD сверху ([CephFS](https://docs.ceph.com/en/latest/cephfs/), [RBD](https://docs.ceph.com/en/latest/rbd/)) | RBD — блочное устройство; CephFS — монтирование ФС | cephadm/контейнеры; нужен кластер демонов; официально рекомендуется запуск в контейнерах |
| GlusterFS | нет нативного (опц. gluster-exporter + Prometheus/Grafana) | `glusterd` + `glusterfsd` userspace; офиц. цифр нет | FUSE-клиент; стриминг неплох, мелкие операции — накладные FUSE | масштабируемое распределённое файловое хранилище ([доки](https://docs.gluster.org/en/latest/)) | FUSE-монтирование (`mount -t glusterfs`) / NFS-Ganesha / libgfapi | пакеты `glusterfs*` в Fedora; подразумевает кластер из нескольких узлов |
| DRBD | нет (drbdadm/drbdmon CLI; LINSTOR — отдельный продукт с UI) | модуль в ядре + пара userspace-утилит; ~32 МиБ на 1 ТиБ (bitmap), по руководству LINBIT | блочная репликация; proto C (sync) ограничен RTT и записью на вторичный узел | HA-зеркало блочного уровня (RAID-1 по сети) ([руководство LINBIT](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/)) | блочное устройство `/dev/drbd*` | DRBD 8.4 в mainline ядра, но в ядрах Fedora/RHEL модуль по умолчанию не собран; DRBD 9 — out-of-tree, ставится из репозитория LINBIT/DKMS |
| rclone mount | да — офиц. web GUI (`rclone gui`/rc) | один Go-процесс; буфер настраивается (`--buffer-size`, VFS-кэш); офиц. цифр нет | FUSE + Go + удалённый протокол; рекомендован `--vfs-cache-mode=writes`; single-user | монтирование облака/удалённых хранилищ, «не полная POSIX ФС», single-user ([доки](https://rclone.org/commands/rclone_mount/)) | FUSE-монтирование; требует сервис-менеджера для автозапуска | пакет `rclone` в Fedora; в Docker — образ rclone/rclone с /dev/fuse |
| WebDAV (davfs2) | нет (клиент; WebDAV-сервер может иметь свой UI, напр. Nextcloud) | FUSE-демон; офиц. цифр нет | FUSE + HTTP; «не высокопроизводительная, для личного использования» ([README](https://savannah.nongnu.org/projects/davfs2)) | монтирование WebDAV-ресурса как локальной ФС, личное использование | FUSE-монтирование; агрессивный кэш | пакет `davfs2` в Fedora; нужен любой WebDAV-сервер (Apache mod_dav, nginx, Nextcloud, rclone serve webdav) |

## Решения

### NFSv3/v4

- Сервер и клиент в Linux — **в ядре** (`nfsd`/`knfsd` на сервере, `nfs`/`nfs4`
  на клиенте). Клиент в зависимости от конфигурации ядра поддерживает NFS 3,
  4.0, 4.1 или 4.2 ([nfs(5)](https://man7.org/linux/man-pages/man5/nfs.5.html)).
- NFSv4 — один протокол поверх TCP с состоянием (clientid/leases); NFSv3 —
  без состояния, отдельный mount-протокол через `rpc.mountd`.
- Официальных бенчмарков пропускной способности нет; архитектурно это
  ядро-ядро без userspace-копий, стриминг близко к линейной скорости LAN.
  Величину «сетевых» накладных официально перечисляет документация LOCALIO:
  skbuff/сокеты/конгестия, кодирование RPC/XDR, двойное копирование page cache
  ([NFS LOCALIO](https://www.kernel.org/doc/html/latest/filesystems/nfs/localio.html)).
- LOCALIO (ядро 6.7+): если NFS-клиент и сервер работают на одной машине в одном
  netns (контейнеры Docker/Podman), RPC-стек обходится целиком и NFS работает
  «на скорости, близкой к нативной». Для нашего сценария не применимо (клиент
  и сервер на разных хостах), но подтверждает, что ядерный путь — самый дешёвый.
- RAM: сервер и клиент в ядре; официальных цифр нет; userspace-часть
  (`rpc.mountd`, `rpc.idmapd`, `nfsdcld`) — единицы–десятки МБ.
- Прозрачность: точка монтирования ФС в VFS; автоподъём через fstab
  (`_netdev`, `x-systemd.automount`). Не блочное устройство.
- Fedora: пакет `nfs-utils` (сервер + клиент). Docker: bind-mount каталога
  хоста или нативный volume `type=nfs`
  ([docker volume create](https://docs.docker.com/reference/cli/docker/volume/create/)).

### SMB/CIFS (Samba)

- `smbd` — сервер, предоставляющий SMB/CIFS, **userspace**, процесс на сессию
  («Each client gets a copy of the server for each session»)
  ([smbd(8)](https://www.samba.org/samba/docs/man/manpages-3/smbd.8.html)).
- Клиент — модуль ядра `cifs`; монтирование `mount -t cifs`/fstab.
- Основные настройки производительности и протоколов — в
  [smb.conf(5)](https://www.samba.org/samba/docs/man/manpages-3/smb.conf.5.html)
  (`server min/max protocol`, `server smb encrypt`, multichannel, VFS-модули).
- Назначение по доке — интероперабельность с Windows/macOS; для пары
  Linux↔Linux это лишний userspace-слой на сервере.
- Официальных цифр RAM/производительности нет.

### SSHFS

- FUSE-клиент поверх SFTP; **ничего не нужно на сервере**, кроме sshd
  ([README](https://github.com/libfuse/sshfs)).
- Проект официально в режиме поддержки, активной разработки нет.
- Назначение — ad-hoc доступ к ФС сервера по SSH, не продакшн-шеринг.
- Накладные: FUSE + SFTP (прикладной протокол поверх SSH), что дороже
  ядерного NFS; официальных чисел нет — см. «Не подтверждённые утверждения».

### iSCSI (LIO + open-iscsi)

- Серверная часть (target) — **в ядре**: LIO/TCM, управление через configfs
  и CLI `targetcli` ([TCM Virtual Device](https://www.kernel.org/doc/html/latest/target/index.html)).
- Клиент (initiator): data-path в ядре (`iscsi_tcp`, `libiscsi`,
  `scsi_transport_iscsi`), control-path — userspace-демон `iscsid` + `iscsiadm`
  ([open-iscsi README](https://github.com/open-iscsi/open-iscsi)).
- Протокол — блочный SCSI поверх TCP ([RFC 7143](https://www.rfc-editor.org/rfc/rfc7143)).
- Прозрачность: честное блочное устройство `/dev/sdX` на клиенте → поверх можно
  LVM, любую ФС. Единственный способ «добавить именно диск».
- Официальных цифр RAM/скорости нет; архитектурно оба конца в ядре.
- Реалии homelab: ФС поверх iSCSI требует чистого открытия/закрытия; сон
  ноутбука даёт ошибки ФС на homelab (в отличие от «устаревшего» NFS-маунта);
  привязка к IP ноутбука; в Docker-контейнерах initiator не используют —
  устройство монтируют на хосте и пробрасывают bind-mount'ом.

### CephFS / Ceph RBD

- CephFS — POSIX-ФС поверх RADOS, метаданные в отдельном пуле через кластер
  MDS, клиенты читают/пишут данные напрямую с OSD
  ([доки CephFS](https://docs.ceph.com/en/latest/cephfs/)).
- RBD — тонкие изменяемые блочные устройства, стрипятся по OSD; клиент — модуль
  ядра `rbd` или `librbd` ([доки RBD](https://docs.ceph.com/en/latest/rbd/)).
- Web-UI: Ceph Dashboard, встроен в `ceph-mgr`
  ([доки Dashboard](https://docs.ceph.com/en/latest/mgr/dashboard/)).
- RAM (официально): 512 МБ–1 ГБ на демон (минимум), 1–2 ГБ (рекомендуется)
  ([hardware recommendations](https://docs.ceph.com/en/latest/start/hardware-recommendations/)).
- Для homelab это тяжело: даже минимальный кластер — несколько демонов (mon, mgr,
  OSD на каждый диск, при CephFS ещё MDS), каждый со своей RAM, плюс рекомендация
  официальной доки запускать всё в контейнерах (cephadm). Отвергнуто как
  избыточное для двух узлов.

### GlusterFS

- Распределённая ФС: тома собираются из «кирпичей» (bricks) на узлах
  доверенного пула; клиенты — FUSE-клиент (`mount -t glusterfs`), NFS-Ganesha
  или libgfapi ([Setting Up Clients](https://docs.gluster.org/en/latest/Administrator-Guide/Setting-Up-Clients/)).
- Нативного Web-UI нет; мониторинг — через gluster-exporter + Prometheus/Grafana.
- Рассчитана на кластер из нескольких узлов; для сценария «ноутбук отдаёт свой
  диск» архитектурно неподходящая и требует демонов на обеих сторонах.
  Отвергнуто.

### DRBD

- Блочная репликация (RAID-1 по сети): в mainline ядре живёт DRBD 8.4
  (`drivers/block/drbd`, [Kconfig](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/block/drbd/Kconfig));
  DRBD 9 — out-of-tree модуль от LINBIT и в ядрах Fedora/RHEL по умолчанию
  не собран.
- Предназначение — HA-зеркало между серверами: в штатном single-primary режиме
  устройство активно только на одном узле. Для «расширить диск homelab» не
  подходит — это зеркало, а не способ прицепить удалённое хранилище (dual-primary
  требует кластерной ФС и оба узла онлайн). Отвергнуто.

### rclone mount

- FUSE-монтирование удалённого хранилища (в т. ч. local, SFTP, WebDAV, S3).
  Официально предупреждают: «не полная POSIX-ФС», «не persistent — нужен
  сервис-менеджер», mount рассчитан на single-user, для сервисов рекомендуют
  `rclone serve nfs/smb/webdav` ([доки](https://rclone.org/commands/rclone_mount/)).
- Есть официальный web GUI (`rclone gui`) и rc-интерфейс.
- Может выступать и сервером (флаги `--nfs`, `--smb`, `--webdav`), но NFS-сервер
  в rclone официально «менее зрел, рекомендуем для одного клиента».
- Для homelab это FUSE-демон на слабой стороне + двойной стек протоколов;
  удобнее для облачных бэкапов, чем для «второго диска».

### WebDAV (davfs2)

- FUSE-драйвер «монтирует WebDAV-ресурс как обычную ФС», разработан для личного
  использования, агрессивно кэширует; по README — не высокопроизводительная ФС
  ([davfs2](https://savannah.nongnu.org/projects/davfs2)).
- Полезен конкретно здесь: в homelab уже есть Nextcloud, который отдаёт WebDAV.
  Для синка личных документов/бэкапов — удобно; для роли «дополнительного
  диска» сервисов — медленнее NFS из-за FUSE + HTTP.

## Короткие упоминания (по желанию, не в таблице)

- **JuiceFS** — POSIX-ФС поверх object storage (S3 и т. п.) с отдельным движком
  метаданных (Redis и др.); клиент — FUSE ([введение](https://juicefs.com/docs/community/introduction/)).
  Интересна, если позже появится object storage, но для пары «ноутбук ↔ homelab»
  добавляет Redis + свой движок — избыточно.
- **SeaweedFS** — распределённое хранилище (master + volume-серверы + filer),
  POSIX-подобный доступ через FUSE/WebDAV/S3; Go-бинарь, легче Ceph, есть web UI
  ([README](https://github.com/seaweedfs/seaweedfs)). Тоже кластерная архитектура,
  для одного диска ноутбука — лишние сущности.

## Рекомендация для вашего случая (NFSv4)

### На ноутбуке (Fedora, сервер)

```text
# /etc/exports
/export/laptop  <node1-lan-cidr>(rw,sync,no_subtree_check,crossmnt)
```

- `sudo systemctl enable --now nfs-server.service`; в firewalld разрешить
  `nfs`, `rpc-bind`, `mountd` (для NFSv4 mount-протокол не нужен, но firewalld
  проще открыть штатными сервисами, или задать фиксированные порты в
  `/etc/nfs.conf`, секция `[mountd]`).
- Сон ноутбука: настроить, чтобы при питании от сети он не засыпал
  (например, `sudo systemctl mask sleep.target suspend.target` или настройки
  GNOME), либо принять, что при сне маунт «протухает».

### На homelab-хосте (клиент)

```text
# /etc/fstab
<client-ip>:/export/laptop  /mnt/laptop  nfs4  _netdev,x-systemd.automount,noatime,vers=4.2,hard,timeo=100,retrans=5  0 0
```

- `x-systemd.automount` — не вешаться при загрузке, если ноутбук выключен;
  монтирование произойдёт по первому обращению.
- `hard` + `timeo`/`retrans` — при пропаже ноутбука операции будут ждать, а не
  отваливаться с ошибкой (мягкий `soft` маунт отдаёт EIO — хуже для баз данных).

### Docker

```text
# Вариант 1: bind-mount уже смонтированной точки
docker run -v /mnt/laptop:/data ...  # или volume в compose

# Вариант 2: нативный NFS-volume (docker смонтирует сам)
docker volume create --driver local \
  --opt type=nfs --opt o=addr=<client-ip>,rw,nfsvers=4 \
  --opt device=:/export/laptop laptop-nfs
```

См. официальную справку
[docker volume create](https://docs.docker.com/reference/cli/docker/volume/create/):
драйвер `local` поддерживает `type=nfs` и `type=cifs`.

### Безопасность и права

- NFSv4 не шифрует данные на канале (шифрование только через Kerberos `krb5p`,
  настраивать в homelab сложно). Достаточно ограничить экспорт подсетью LAN
  (`<node1-lan-cidr>`) + firewall.
- UID-маппинг: AUTH_SYS передаёт uid. UID пользователя ноутбука (обычно 1000)
  должен совпадать с UID на homelab (или наоборот — задать нужный). Для
  контейнеров выставлять PUID/PGID соответствующими.
- `root_squash` (по умолчанию) маппит корня (uid 0, как в контейнерах по
  умолчанию) в nobody — если контейнер пишет как root, файлы окажутся
  nobody:nobody. Решения: запускать контейнеры с PUID=1000 или экспортировать
  с `no_root_squash` для доверенной подсети (осознанный компромисс в homelab).
- Не бэкап: единственная копия данных — на ноутбуке.

## Ограничения и оговорки

- Сценарий целиком зависит от аптайма ноутбука; HA здесь нет по построению.
- Пропускная способность ограничена 1GbE (~110–118 МБ/с) и одним TCP-потоком
  на маунт; для локальных NVMe это медленно, для медиа и файловых сервисов —
  обычно достаточно. Нужно быстрее — 2.5/10GbE или SMB multichannel.
- NFS отдаёт файловую точку монтирования, а не блочное устройство: LVM и
  файловые системы поверх NFS невозможны. Если это критично — iSCSI.
- Docker поверх отвалившегося маунта: если ноутбук выключен, bind-mount
  показывает пустой/старый каталог, и контейнеры могут «увидеть пустоту».
  `x-systemd.automount` + запуск Docker после network-online это смягчают;
  нативный `type=nfs` volume монтируется лениво самим Docker.
- После сна ноутбука NFS-маунт на клиенте «протухает»: TCP-сессии рвутся,
  hard-маунт вернётся после перезапуска сервера (обычно достаточно
  `systemctl restart nfs-server` и доступа).

## Не подтверждённые утверждения

- Для NFS/SMB/iSCSI/Gluster/davfs2/SSHFS/rclone нет официальных цифр
  потребления RAM и пропускной способности — в таблице только архитектурные
  оценки (ядро vs userspace, FUSE vs kernel), без локальных замеров.
- FUSE-накладные: цифры (в среднем ~30% и выше на мелких/метаданных операциях)
  взяты из академической работы «To FUSE or Not to FUSE»
  ([Vangoor et al., FAST'17](https://www.usenix.org/conference/fast17/technical-sessions/presentation/vangoor)),
  не из официальных доков.
- Цифра «~32 МиБ RAM на 1 ТиБ» для DRBD — из официального руководства LINBIT;
  вытащить точную цитату из JS-генерируемой страницы не удалось.
- Статус поддержки SMB multichannel и шифрования SMB3 в конкретных версиях
  Samba стоит проверить по release notes перед внедрением.

## Основные источники

- NFS: [nfs(5)](https://man7.org/linux/man-pages/man5/nfs.5.html),
  [kernel.org filesystems/nfs](https://www.kernel.org/doc/html/latest/filesystems/nfs/index.html),
  [NFS LOCALIO](https://www.kernel.org/doc/html/latest/filesystems/nfs/localio.html)
- Samba: [smbd(8)](https://www.samba.org/samba/docs/man/manpages-3/smbd.8.html),
  [smb.conf(5)](https://www.samba.org/samba/docs/man/manpages-3/smb.conf.5.html)
- SSHFS: [README](https://github.com/libfuse/sshfs)
- iSCSI: [TCM Virtual Device (kernel target)](https://www.kernel.org/doc/html/latest/target/index.html),
  [open-iscsi README](https://github.com/open-iscsi/open-iscsi),
  [RFC 7143](https://www.rfc-editor.org/rfc/rfc7143)
- Ceph: [CephFS](https://docs.ceph.com/en/latest/cephfs/),
  [RBD](https://docs.ceph.com/en/latest/rbd/),
  [hardware recommendations](https://docs.ceph.com/en/latest/start/hardware-recommendations/),
  [Ceph Dashboard](https://docs.ceph.com/en/latest/mgr/dashboard/)
- GlusterFS: [документация](https://docs.gluster.org/en/latest/),
  [Setting Up Clients](https://docs.gluster.org/en/latest/Administrator-Guide/Setting-Up-Clients/)
- DRBD: [руководство LINBIT](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/),
  [Kconfig драйвера в mainline](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/block/drbd/Kconfig)
- rclone: [rclone mount](https://rclone.org/commands/rclone_mount/),
  [rclone gui](https://rclone.org/gui/)
- davfs2: [Savannah](https://savannah.nongnu.org/projects/davfs2)
- Docker: [docker volume create](https://docs.docker.com/reference/cli/docker/volume/create/),
  [volumes](https://docs.docker.com/engine/storage/volumes/)
- FUSE overhead (академический источник): [«To FUSE or Not to FUSE», FAST'17](https://www.usenix.org/conference/fast17/technical-sessions/presentation/vangoor)
