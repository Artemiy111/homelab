# Блочные протоколы и кластерные/распределённые файловые системы: разбор для homelab

Дата проверки: 2026-10-13.

Глава исследования «Протоколы разделяемого (сетевого) хранилища». Обзор,
сводные таблицы по всем категориям и выводы для homelab — в
[`overview.md`](overview.md).

Отчёт посвящён **параметрам протоколов и систем**: блочные протоколы по сети,
SAN-кластерные ФС и распределённые/кластерные ФС. Все утверждения привязаны
к первоисточникам (RFC, официальная документация, man-страницы, исходный код);
ссылки даны inline. Если официальных цифр нет — это написано прямо.

## Вывод

1. **Блочные протоколы — это транспорт для SCSI/NVMe, а не «сетевая ФС».**
   Они дают честное блочное устройство (`/dev/sdX`, `/dev/nvmeXnY`), поверх которого
   можно наложить LVM и любую ФС, но **само устройство не знает о ФС** и не даёт
   ни журнала, ни целостности, ни защиты от одновременного монтирования.
   Кто видит LUN — видит все данные целиком ([RFC 7143, §9.5](https://www.rfc-editor.org/rfc/rfc7143.txt)).

2. **iSCSI — единственный блочный протокол «из коробки» в Linux без специального
   железа**, с аутентификацией (CHAP/SRP/Kerberos) и опциональным IPsec
   ([RFC 7143, §12](https://www.rfc-editor.org/rfc/rfc7143.txt)). Клиент и target —
   в ядре (`iscsi_tcp`/`libiscsi`, LIO), управление — userspace (`iscsid`, `targetcli`).

3. **NVMe-oF — современная замена iSCSI**: TCP-транспорт работает по обычной
   сети, RDMA/RoCE и FC — по специальной. В NVMe 2.0 (июнь 2021) NVMe-oF влит в
   базовую спецификацию, добавлены in-band аутентификация DH-HMAC-CHAP и TLS 1.3
   для TCP ([NVM Express](https://nvmexpress.org/nvme-2-0-specifications-support-for-fabrics-and-multi-domain-subsystems/)).

4. **Специализированные блочные транспорты homelab не нужны**: FC/FCoE и iSER/SRP
   требуют HBA и (для RDMA) сеть с RoCE/InfiniBand; AoE — без IP, без
   аутентификации и без маршрутизации; SMB Direct — RDMA и, по сути, Windows-центричен.
   FCoE официально помечен как deprecated у Broadcom (Fabric OS 9.2.2)
   ([Broadcom TechDocs](https://techdocs.broadcom.com/us/en/fibre-channel-networking/fabric-os/fabric-os-administration/9-2-x/understanding-fcoe-92x-admin.html)).

5. **Кластерные SAN-ФС (OCFS2, GFS2, VMFS) осмысленны только при ≥2 узлах,
   одновременном доступе к одному LUN и полноценном cluster-стеке** (DLM, fencing,
   lvmlockd/o2cb). GFS2 напрямую требует кворума (`no-quorum-policy=freeze`)
   ([Red Hat](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_high_availability_clusters/assembly_configuring-gfs2-in-a-cluster-configuring-and-managing-high-availability-clusters)),
   OCFS2 требует stack `o2cb` с disk-heartbeat и self-fencing
   ([o2cb(7)](https://manpages.debian.org/testing/ocfs2-tools/o2cb.7.en.html)).

6. **Обычную ФС (ext4/XFS) нельзя монтировать на одном LUN с двух хостов.** Это не
   «не рекомендуется», а не поддерживается: у ext4/XFS нет распределённых блокировок
   и согласованности кэшей. Именно поэтому существуют кластерные ФС. Прямая цитата
   LINBIT: «DRBD cannot auto-detect file system corruption or add active-active
   clustering capability to file systems like ext3 or XFS»
   ([DRBD 9 User Guide, §1.1](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/)).

7. **Для homelab на 1–2 узлах разумны**: iSCSI/NVMe-oF (как «честный диск»),
   DRBD (зеркало HA между двумя хостами) и «лёгкие» распределённые ФС в
   single-node/2-node режиме — JuiceFS (с внешним object storage), SeaweedFS,
   MooseFS Community. Ceph технически умеет single-host (`--single-host-defaults`),
   но официально «generally not suitable for production».

8. **Что не осмысленно в homelab**: OCFS2/GFS2/VMFS (нет второго хоста с общим LUN
   и fencing), 3+-узловые Ceph/GlusterFS/Lustre/BeeGFS ради одного диска,
   **LizardFS** (проект заброшен, последний релиз ~2016) и **AoE** (нет
   аутентификации/шифрования и нет маршрутизации).

9. **Безопасность распределённых ФС различается радикально**: у Ceph аутентификация
   есть (cephx), но по умолчанию **не шифрование** — шифрование только в `secure`
   режиме msgr2 ([Ceph msgr2](https://docs.ceph.com/en/latest/rados/configuration/msgr2/)).
   У JuiceFS — клиентское шифрование AES-256-GCM/ChaCha20-Poly1305
   ([JuiceFS](https://juicefs.com/docs/community/security/encryption/)). У Lustre,
   BeeGFS, MooseFS, GlusterFS, OCFS2, GFS2 — своей шифрации транспорта нет
   (Lustre — GSS/Kerberos, GlusterFS — TLS, остальные — «доверенная сеть»).

10. **Лицензии и зрелость**: Ceph (LGPL-2.1/GPL-2.0, фонд Ceph Foundation),
    GlusterFS (GPL-2.0, коммерческий продукт Red Hat завершён 31.12.2024),
    Lustre (GPL-2.0, OpenSFS), JuiceFS (Apache-2.0 Community), SeaweedFS
    (Apache-2.0), MooseFS (GPLv2 Community + проприетарный Pro), BeeGFS
    (Community с лимитом 1200 ТБ + Enterprise), XtreemFS (New BSD, но проект
    малоактивен), LizardFS (GPLv3, заброшен).

## Сравнительные таблицы

### Таблица 1. Блочные протоколы по сети

| Протокол | Клиент / сервер; ядро vs userspace | Топология и порты | Аутентификация и шифрование | Прозрачность на диске | Целостность/HA | Лицензия и статус |
|---|---|---|---|---|---|---|
| **iSCSI** | Клиент: data-path в ядре (`iscsi_tcp`, `libiscsi`), control — `iscsid`; сервер: LIO в ядре + `targetcli`/configfs ([TCM](https://www.kernel.org/doc/html/latest/target/index.html), [open-iscsi](https://github.com/open-iscsi/open-iscsi)) | TCP/IP; IANA-порт 3260; любые расстояния (RTT-чувствителен) | AuthMethod: CHAP, SRP, Kerberos; шифрование — IPsec ([RFC 7143 §9.3, §12](https://www.rfc-editor.org/rfc/rfc7143.txt)); digests CRC32C | Сырой блочный LUN → `/dev/sdX`, можно LVM/любую ФС; снять диск и смонтировать локально нельзя, пока LUN не отключён | Multi-path, MC/S (MaxConnections), ErrorRecoveryLevel; HA — внешняя (MPIO) | Открытый стандарт (IETF); зрелый |
| **iSER** | Ядро `ib_iser` (Linux); RDMA-Capable Controller | InfiniBand RC или iWARP/RoCE; не TCP | Наследует iSCSI (CHAP и т. д.); целостность на уровне RDMA (digests = None) ([RFC 7145](https://www.rfc-editor.org/rfc/rfc7145.txt)) | Как iSCSI: сырой SCSI | Multi-path; зависит от RDMA-фабрики | Стандарт (RFC 7145, обsolete 5046); зрелый, но требует RNIC/HCA |
| **NVMe-oF (TCP)** | Ядро: host `nvme-tcp`, target `nvmet-tcp` ([NVMe Subsystem docs](https://docs.kernel.org/nvme/index.html)); userspace: SPDK/nvmet | TCP/IP; IANA 4420 (+8009 discovery); любые расстояния | In-band DH-HMAC-CHAP (NVMe 2.0), TLS 1.3 для TCP ([NVM Express](https://nvmexpress.org/nvme-2-0-specifications-support-for-fabrics-and-multi-domain-subsystems/)) | Сырой NVMe-блок → `/dev/nvmeXnY` | Native multipath; ANA | Открытая спецификация NVMe; активно развивается |
| **NVMe-oF (RDMA/RoCE)** | Ядро `nvme-rdma`/`nvmet-rdma`; или SPDK userspace | InfiniBand / RoCE; не TCP | Как TCP (DH-HMAC-CHAP); целостность RDMA | Сырой NVMe-блок | Native multipath | Открытая спецификация; требует RDMA-железа |
| **NVMe/FC** | Ядро `nvme-fc`/`nvmet-fc`; HBA | Fibre Channel fabric; не IP | Zoning по WWPN; отдельная спецификация FC-NVMe (T11) | Сырой NVMe-блок | Multipath (FC) | Требует FC HBA и switch |
| **Fibre Channel / FCP** | HBA + драйвер (Broadcom/Marvell); FCP поверх FC-PH/FC-FS | FC fabric (или point-to-point); отдельная L2-сеть, не IP | Zoning по WWPN/WWNN (доступ), без шифрования на уровне FC | Сырой SCSI-блок | Multipath; FC-FS/FC-LS (T11) | Открытые стандарты INCITS T11 ([incits.org](https://www.incits.org/committees/t11)); зрелый, дорогой |
| **FCoE** | Converged Network Adapter (CNA) + DCB | Ethernet L2 (без потерь), не маршрутизируется | Zoning FC; DCB | Сырой SCSI-блок | Multipath | **Deprecated** у Broadcom с Fabric OS 9.2.2 ([TechDocs](https://techdocs.broadcom.com/us/en/fibre-channel-networking/fabric-os/fabric-os-administration/9-2-x/understanding-fcoe-92x-admin.html)) |
| **AoE** | Клиент — модуль ядра `aoe` (`drivers/block/aoe`, major 152) ([kernel](https://docs.kernel.org/5.16/admin-guide/aoe/index.html)); сервер — userspace `vblade`/`aoetools` | Raw Ethernet (EtherType), **не IP**, только локальный L2-домен | **Аутентификации и шифрования нет** | Сырой ATA-блок → `/dev/etherd/eX.Y` | Нет mirroring; HA нет | Открытая спецификация (Brantley Coile); в Linux есть, но узкая ниша |
| **NBD** | Клиент — модуль ядра (transmission), userspace handshake; сервер полностью userspace ([kernel NBD](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/nbd.html)) | TCP (IANA 10809) или Unix-сокеты | TLS опционален (`NBD_OPT_STARTTLS`); **аутентификация не специфицирована** — «implementation dependent» ([proto.md](https://github.com/NetworkBlockDevice/nbd/blob/master/doc/proto.md)) | Диапазон байт; сервер может отдавать файл или блочное устройство | Нет HA в протоколе; `FLUSH`/`FUA` | Открытый протокол (GPL-2.0 инструменты); простой, не для продакшн-стораджа |
| **SRP** | Ядро `ib_srp` (Linux) | InfiniBand RC; не TCP | Аутентификация на уровне IB (кроме того SRP может использовать iSCSI CHAP-подобную) | Сырой SCSI-блок | Multipath IB | Стандарт IETF ([RFC 5046](https://www.rfc-editor.org/rfc/rfc5046.txt)); ниша InfiniBand |
| **SMB Direct** | Windows Server 2012+ и Windows 10/11 (client-only для 10/11) ([Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-direct)) | RDMA (RoCE/iWARP/IB); включается через SMB Multichannel | Шифрование SMB3 + RDMA только с WS2022/Windows 11; AES-128/256 | SMB-шара, не блочное устройство | Failover между RDMA-интерфейсами | Проприетарный Microsoft; подробнее — в главе [`file-level-protocols.md`](file-level-protocols.md) |
| **DRBD** | Ядро (модуль) + userspace (`drbdadm`, `drbdsetup`, `drbdmeta`); out-of-tree для 9.x | TCP или RDMA-транспорт; прямой хост-хост | С 9.2.6 — TLS-шифрование трафика (ktls); аутентификация соединений (HMAC) в mainline ([Kconfig](https://github.com/torvalds/linux/blob/master/drivers/block/drbd/Kconfig), [DRBD 9 Guide](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/)) | Сырое блочное зеркало `/dev/drbdX`; данные = блоки, лежащие на «нижнем» устройстве | RAID-1 по сети; протоколы A/B/C; кворум; split-brain | GPL-2.0 (модуль), LINBIT; 9.x — out-of-tree |

### Таблица 2. SAN-кластерные ФС

| ФС | ОС | Требуемый кластерный слой | Узлы и кворум | Аутентификация и шифрование | Прозрачность | Статус/лицензия |
|---|---|---|---|---|---|---|
| **OCFS2** | Linux (Oracle Linux, openSUSE/SLES; in-tree) | `o2cb` (o2nm, o2hb disk-heartbeat, o2net, o2dlm) или pcmk | Нужны ≥2 узла на одном LUN; disk-heartbeat + self-fencing; global heartbeat для многих маунтов | POSIX-права, ACL/xattr; шифрования транспорта нет | «Shared-disk cluster FS» — нельзя питать ext4-инструментами; монтируется только OCFS2-драйвером | GPL-2.0; in-tree; Oracle |
| **GFS2** | Linux (RHEL + community) | Pacemaker/Corosync + `dlm` (dlm_controld) + `lvmlockd` + fencing (STONITH) | Нужны ≥2 узла; **требует кворума** (`no-quorum-policy=freeze`); журнал на каждый узел | POSIX-права, ACL, квоты; шифрование — только через LUKS-слой | Своя ФС `mkfs.gfs2`; не читается обычными инструментами | GPL-2.0; RHEL Resilient Storage |
| **VMFS** | Только VMware ESXi | ESXi cluster + ATS-локирование | Нужны ESXi-хосты, разделяющие LUN | Аутентификация vSphere; шифрование — vSphere encryption/self-encrypting drives | Проприетарный формат; вне ESXi не монтируется | Проприетарный VMware/Broadcom; enterprise-only |

### Таблица 3. Распределённые и кластерные ФС

| Система | Клиенты / ОС | Ядро или userspace | Мин. узлы | Аутентификация / шифрование | Прозрачность на диске | Офиц. ресурсы | Лицензия / статус |
|---|---|---|---|---|---|---|---|
| **Ceph** (RADOS/RBD/CephFS) | Linux (kernel `rbd`, `ceph`/CephFS), FUSE, Windows (ceph-dokan), BSD | Ядро + демоны в контейнерах (cephadm) | Офиц. кластер ≥3 mon; есть `--single-host-defaults`, но «generally not suitable for production» | cephx (аутентификация) + msgr2 `secure` режим (AES-GCM шифрование); caps; kерberos в планах | Объекты в BlueStore (RocksDB + BlueFS) — на другом хосте не читаются | OSD ≥4 GiB RAM (default `osd_memory_target`), mon ≥5 GB, MDS ≥8 GiB; mon 2 cores, MDS 2 cores ([minimum-hardware](https://docs.ceph.com/en/latest/start/minimum-hardware/), [cpu-memory](https://docs.ceph.com/en/latest/start/hardware-cpu-memory/)) | LGPL-2.1/GPL-2.0; Ceph Foundation; активен |
| **GlusterFS** | Linux (FUSE, NFS-Ganesha, libgfapi); Windows-клиента нет | userspace (`glusterd`, `glusterfsd`) | ≥1 «brick»; реплика/arbiter требуют ≥3 узлов для 3-way | `auth.allow/auth.reject`; TLS (glusterfs.ssl); права POSIX, квоты | brick = каталог-экспорт на XFS; рядом служебный `.glusterfs` | Официальных цифр RAM/CPU нет | GPL-2.0; RHGS EOL 31-Dec-2024 ([Red Hat lifecycle](https://access.redhat.com/support/policy/updates/rhs)); развитие сообществом замедлилось |
| **Lustre** | Linux (клиент out-of-tree; сервер out-of-tree) | Ядро (модули) | MGS+MGT+MDT/MDS+OST/OSS; минимум несколько узлов | GSS/Kerberos, nodemap, root squash; шифрования транспорта нативно нет | ldiskfs (ext4-вариант) или ZFS; объекты/OI — на другом хосте не читаются | Официальных цифр RAM/CPU нет | GPL-2.0; OpenSFS/DDN; HPC-ориентирован |
| **BeeGFS** | Linux; Windows-клиент не заявлен как поддерживаемый | Клиент — patchless kernel-модуль, серверы userspace | ≥1 management + metadata/storage | connAuthFile (общий токен); шифрования транспорта нативно нет | Chunk-файлы в storage targets; метаданные в БД — напрямую не читаются | Официальных цифр RAM/CPU нет | Available Source (не OSI-«открытый»): Community-лицензия с лимитом 1200 ТБ, Enterprise — платно ([licensing](https://doc.beegfs.io/latest/advanced_topics/licensing.html)) |
| **MooseFS** | Linux, FreeBSD, macOS (Community); Windows — только Pro | FUSE (`mfsmount`), C API, блочное устройство | 1 Master + chunkservers; metalogger — для восстановления | `mfsexports.cfg`; в Pro — взаимная аутентификация модулей общим auth-кодом | Данные — «чанки» на chunkserver'ах; метаданные на Master — напрямую не читаются | Официальных цифр RAM/CPU нет | Community — GPLv2; Pro — проприетарный ([architecture](https://moosefs.com/architecture.html)) |
| **JuiceFS** | Linux, macOS, Windows (WinFsp); FUSE | userspace (Go) | 1 узел возможен (SQLite); для HA — внешний движок метаданных | Аутентификация движка метаданных; клиентское шифрование at-rest (AES-256-GCM / ChaCha20 / SM4-GCM); TLS in transit | Чанки-объекты в object storage (сжатые/шифрованные); метаданные в Redis/MySQL/TiKV/SQLite — напрямую файлы не читаются | Официальные бенчмарки есть (см. Performance) | Apache-2.0 (Community); Enterprise — отдельно ([intro](https://juicefs.com/docs/community/introduction/)) |
| **SeaweedFS** | Linux, macOS, Windows; FUSE/S3/WebDAV/SFTP/HDFS | userspace (Go, один бинарь `weed`) | 1 узел (`weed mini` — «fine for single-node production»); 3 master для Raft | S3-креды/IAM/STS; JWT для volume; mTLS; AES256-GCM at rest | Append-only volume-файлы (`.dat`/`.idx`), 16-байтовая запись индекса на blob | Официальные бенчмарки в README (одна машина) | Apache-2.0; активен ([README](https://github.com/seaweedfs/seaweedfs)) |
| **HDFS** | Linux/Windows/macOS (Java); FUSE — стороннее | userspace (JVM) | NameNode (1 или HA pair) + DataNodes | Kerberos обязателен в secure mode; SASL на data transfer; TDE at rest | Блоки + `.meta` (checksum) на DataNode; fsimage на NameNode — напрямую не читаются | Официальных цифр RAM/CPU в docs нет (кроме объёма кучи NN) | Apache-2.0; Apache Hadoop; активно |
| **LizardFS** | Linux (FUSE), macOS; Windows — отдельный клиент | userspace | Master + chunkservers | auth-код / mfsexports (как MooseFS) | Чанки; **проект заброшен** | Официальных цифр нет | GPLv3, но последний релиз 3.12.0 (~9 лет назад) ([repo](https://github.com/lizardfs/lizardfs)) |
| **XtreemFS** | Linux (FUSE), macOS | userspace (DIR, MRC, OSD) | DIR + MRC + OSD | «unauthenticated and unencrypted TCP by default», опционально SSL | Объекты на OSD; напрямую не читаются | Официальных цифр нет | New BSD (с 1.3); проект малоактивен ([FAQ](https://www.xtreemfs.org/faq.php)) |
| **NFS-Ganesha** | Linux (userspace NFS-сервер); FreeBSD (VFS FSAL) | userspace | 1 демон-прокси | Kerberos (krb5/krb5i/krb5p), NFSv4 ACL, делегирование бэкенду | Прокси — на диске ничего нового не появляется | Официальных цифр нет | LGPLv3; активно ([wiki](https://github.com/nfs-ganesha/nfs-ganesha/wiki/Fsalsupport)) |

## Подробный разбор

### Блочные протоколы

#### iSCSI

- Спецификация — [RFC 7143](https://www.rfc-editor.org/rfc/rfc7143.txt) (Internet Standard,
  консолидация 3720/3980/4850/5048), SCSI поверх TCP.
- Linux: initiator data-path в ядре (`iscsi_tcp`, `libiscsi`, `scsi_transport_iscsi`),
  управление — userspace `iscsid`/`iscsiadm` ([open-iscsi](https://github.com/open-iscsi/open-iscsi));
  target — LIO/TCM в ядре, настройка через configfs (`targetcli`)
  ([TCM Virtual Device](https://www.kernel.org/doc/html/latest/target/index.html)).
- Порты: IANA 3260/tcp.
- Аутентификация: `AuthMethod` = CHAP, SRP, Kerberos (`krb5`) — раздел 12 RFC;
  transport-шифрование — IPsec (раздел 9.3); целостность — `HeaderDigest`/`DataDigest`
  (CRC32C). MC/S, `MaxConnections`, `ErrorRecoveryLevel` описаны там же.
- Прозрачность: initiator видит блочный LUN; на диске — блоки SCSI, никакой
  собственной ФС/структуры у iSCSI нет.
- Официальных цифр пропускной способности/RAM нет (ядро-ядро).

#### iSER

- [RFC 7145](https://www.rfc-editor.org/rfc/rfc7145.txt) (obsoletes RFC 5046).
  Даёт RDMA data-placement для iSCSI: RDMA-Capable Protocol — iWARP над TCP или
  InfiniBand Reliable Connected.
- Важные следствия: «iSCSI header and data digests are negotiated to "None" for
  iSCSI/iSER sessions», целостность обеспечивает RCaP (CRC в IB RC / MPA-CRC в iWARP).
- Реализация Linux — модуль `ib_iser`; требует RNIC/HCA.

#### NVMe-oF

- С [NVMe 2.0](https://nvmexpress.org/nvme-2-0-specifications-support-for-fabrics-and-multi-domain-subsystems/)
  (июнь 2021) спецификация NVMe-oF **влита в базовую**, а транспорты вынесены в
  отдельные документы: TCP, RDMA, PCIe; FC — отдельная (FC-NVMe, T11).
- Безопасность: in-band аутентификация DH-HMAC-CHAP; TLS 1.3 для TCP.
- Linux: подсистема NVMe в ядре (`nvme-tcp`/`nvmet-tcp` host/target, `nvme-rdma`/
  `nvmet-rdma`, `nvme-fc`/`nvmet-fc`), см. [NVMe Subsystem docs](https://docs.kernel.org/nvme/index.html).
  Порт NVMe/TCP — IANA 4420, discovery — 8009. Точный релиз ядра, в котором появился
  `nvme-tcp`, в официальной документации не указан (см. «Не подтверждённые утверждения»).
- Прозрачность: сырое NVMe-устройство (`/dev/nvmeXnY`), ни ФС, ни метаданных поверх.

#### Fibre Channel и FCP

- Стандарты INCITS T11: FC-PH/FC-FS (framing, signalling, link services),
  FCP (SCSI over FC), FC-GS (services), FC-BB (backbones) — [incits.org/committees/t11](https://www.incits.org/committees/t11).
- Требуется FC HBA и (обычно) FC switch; адресация — WWNN/WWPN, доступ — zoning.
  Без специального железа FC не существует; в homelab не применяется.
- Прозрачность: сырой SCSI-блок, как у iSCSI.

#### FCoE

- Encapsulation FC поверх Ethernet (семейство FC-BB-5/FC-BB-6), требует Converged
  Network Adapter и DCB (lossless Ethernet).
- Broadcom официально: «FCoE is deprecated in Fabric OS v9.2.2. FCoE will be
  obsoleted» ([TechDocs](https://techdocs.broadcom.com/us/en/fibre-channel-networking/fabric-os/fabric-os-administration/9-2-x/understanding-fcoe-92x-admin.html)).
  Технология уходит.

#### AoE (ATA over Ethernet)

- Протокол Coile/Brantley: ATA-команды прямо в Ethernet-кадрах, **без IP**.
- Реализация Linux — `drivers/block/aoe` (major 152), документация
  [ATA over Ethernet (AoE)](https://docs.kernel.org/5.16/admin-guide/aoe/index.html);
  сервер — userspace `vblade`/`aoetools`.
- Нет аутентификации, нет шифрования, нет маршрутизации (только один L2-домен).
  Годится разве что как «второй диск» в доверенной лабораторной сети.

#### NBD (Network Block Device)

- [kernel NBD](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/nbd.html):
  «The nbd kernel module need only be installed on the client system, as the
  nbd-server is completely in userspace».
- Протокол [proto.md](https://github.com/NetworkBlockDevice/nbd/blob/master/doc/proto.md):
  newstyle negotiation, порт 10809; TLS — опционально (`NBD_OPT_STARTTLS`);
  аутентификация/авторизация **не специфицированы**: «This standard does not specify
  authentication and authorisation ... this is implementation dependent».
- Прозрачность: диапазон байт; сервер может отдавать файл, устройство или их набор.

#### SRP (SCSI RDMA Protocol)

- [RFC 5046](https://www.rfc-editor.org/rfc/rfc5046.txt). Linux — `ib_srp`.
  Ниша — InfiniBand; для Ethernet-реалий не применим.

#### SMB Direct

- [Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-direct):
  RDMA-транспорт для SMB3, включается автоматически; требует SMB Multichannel;
  Windows 10/11 — **client-only** («can't act as an SMB Direct server»).
- С Windows Server 2022/Windows 11 SMB Direct поддерживает шифрование (AES-128/256),
  тогда как раньше включение шифрования ломало RDMA data placement.

#### DRBD и LINSTOR

- DRBD — «software-based, shared-nothing, replicated storage solution mirroring the
  content of block devices ... between hosts»; ядро + userspace
  ([DRBD 9 User Guide](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/)).
- Ресурсы (официально): «about 32MiB of RAM per 1TiB of storage» для битмапа при
  гранулярности 4 KiB (с DRBD 9.3 — грубее, 1 MiB/бит → 128 MiB на 1 PiB);
  max device size 1 PiB; до 32 узлов на ресурс, «clusters of more than five nodes
  are not recommended»; min kernel 2.6.32 (9.0) / 3.10 (9.1); CPU: amd64/arm64/ppc64le/s390x.
- Режимы: single-primary (любая обычная ФС, канонично для HA) и dual-primary
  («usually requires the use of a shared cluster file system that uses a distributed
  lock manager», напр. GFS/OCFS2).
- Протоколы: A (async), B (memory-sync), C (sync, «guaranteed not to lead to any data loss»
  при потере одного узла).
- Транспорты: TCP и, с 9.2.0, открытый RDMA (`drbd_transport_rdma`, IB/iWARP/RoCE).
  Шифрование трафика — TLS с 9.2.6 (ktls-utils); до этого только LUKS-слой.
- **Mainline vs out-of-tree**: в mainline Linux присутствует драйвер DRBD
  (`BLK_DEV_DRBD`, shared-nothing, dual-primary требует cluster FS, аутентификация
  через `CRYPTO_HMAC`) — [Kconfig](https://github.com/torvalds/linux/blob/master/drivers/block/drbd/Kconfig);
  актуальная ветка 9 — out-of-tree (LINBIT, DKMS), и LINBIT отдельно ведёт
  руководство для 8.4. В Kconfig номер версии не указан (см. «Не подтверждённые утверждения»).
- LINSTOR — отдельный продукт LINBIT для управления DRBD-ресурсами (в меню LINBIT:
  LINSTOR, LINBIT SDS, DRBD Reactor) — [linbit.com](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/).

### SAN-кластерные ФС

#### OCFS2

- [Kernel docs](https://docs.kernel.org/filesystems/ocfs2.html): «OCFS2 is a general
  purpose extent based shared disk cluster file system with many similarities to ext3».
  Инструменты — пакет `ocfs2-tools` (`mount.ocfs2`, `ocfs2_hb_ctl`).
- Кластерный стек — [o2cb(7)](https://manpages.debian.org/testing/ocfs2-tools/o2cb.7.en.html):
  in-kernel, включает node manager (o2nm), disk heartbeat (o2hb), сетевой агент
  (o2net), распределённый DLM (o2dlm) и `dlmfs`. Требует `kernel.panic_on_oops = 1`
  и `kernel.panic = 30`; при медленном I/O узел выполняет self-fence («relies on
  kernel timers and pci bus reset»). Heartbeat — local или global (рекомендован при
  ≥3 маунтах).
- Ограничения (kernel docs): нет directory change notification (F_NOTIFY) и нет
  distributed caching (F_SETLEASE). Есть POSIX ACL (`acl`) и xattr (`user_xattr`),
  `coherency=full|buffered`.
- Официальный обзор — [Oracle: Managing OCFS2](https://docs.oracle.com/en/operating-systems/oracle-linux/9/ocfs2/OL9-OCFS2.pdf);
  ОС — Linux.

#### GFS2

- Red Hat — первичная документация
  ([RHEL 9, GFS2 in a cluster](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_high_availability_clusters/assembly_configuring-gfs2-in-a-cluster-configuring-and-managing-high-availability-clusters)).
- Требуется: репозиторий Resilient Storage, пакеты `dlm`, `gfs2-utils`, `lvm2-lockd`;
  DLM-ресурс + `lvmlockd` (общие VG `vgcreate --shared`); fencing обязателен.
- Ключевая цитата: «unlike most resources, GFS2 requires quorum to function ... set
  `no-quorum-policy` to `freeze` when GFS2 is in use».
- Журнал на каждый узел: `mkfs.gfs2 -j<N> -p lock_dlm -t <Cluster>:<FS>`.
- Прозрачность: ФС монтируется на нескольких узлах одним драйвером; обычными
  инструментами (ext4) не читается. Шифрование — только LUKS поверх.

#### VMFS (кратко)

- Проприетарная кластерная ФС VMware, требует ESXi и разделяемого LUN; locking —
  через ATS (atomic test and set) и on-disk locks
  ([Broadcom: vSphere VMFS Datastore Concepts](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-storage/working-with-datastores-in-vsphere-storage-environment/vsphere-vmfs-datastore-concepts-and-operations.html)).
- Вне ESXi не монтируется; в homelab без vSphere не применима (enterprise-only продукт).

#### Почему нельзя монтировать обычную ФС дважды

- ext4/XFS не имеют распределённых блокировок и согласования кэшей между узлами.
  Именно поэтому существуют OCFS2/GFS2: их документация определяет их как
  «shared disk cluster file system», а сама необходимость cluster-стека (DLM, heartbeat,
  fencing) и есть доказательство того, что без него одновременное монтирование
  небезопасно.
- Прямая формулировка LINBIT про DRBD: «DRBD cannot auto-detect file system
  corruption or add active-active clustering capability to file systems like ext3
  or XFS» ([DRBD 9 Guide §1.1](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/));
  и Kconfig: «on top of dual-Primary DRBD utilizing a cluster file system is necessary
  to maintain for cache coherency» ([Kconfig](https://github.com/torvalds/linux/blob/master/drivers/block/drbd/Kconfig)).
- Практический вывод: если один LUN виден двум хостам, либо монтирует **только один**
  (active/passive, например DRBD single-primary + failover), либо нужна **кластерная**
  ФС с DLM/fencing.

### Распределённые ФС

#### Ceph (RADOS, RBD, CephFS)

- RADOS — объектное ядро; RBD — блочные устройства; CephFS — POSIX поверх MDS
  ([docs.ceph.com](https://docs.ceph.com/en/latest/)).
- RAM/CPU (официально, [minimum-hardware](https://docs.ceph.com/en/latest/start/minimum-hardware/)):
  `ceph-osd` ≥4 GiB RAM, 1 поток min / 3 рекомендовано на HDD, 4/6 на NVMe SSD;
  `ceph-mon` 2 cores, ≥5 GB RAM, 100 GB SSD; `ceph-mds` 2 cores, ≥8 GiB RAM.
  [cpu-memory](https://docs.ceph.com/en/latest/start/hardware-cpu-memory/): «Very small
  clusters — 32 GiB» RAM для mon/mgr; `osd_memory_target` default 4 GiB; «budget at
  least 20 percent RAM above the sum of osd_memory_target values».
- Single-node: `cephadm bootstrap --single-host-defaults` — «Such clusters are generally
  not suitable for production» ([cephadm install](https://docs.ceph.com/en/latest/cephadm/install/)).
- Сеть: mon v2 на порту 3300, legacy v1 — 6789. Режимы msgr2: `crc` (аутентификация
  + crc32c, **без** секретности) и `secure` (полное шифрование AES-GCM)
  ([msgr2](https://docs.ceph.com/en/latest/rados/configuration/msgr2/)).
- Авторизация: cephx + caps по daemon/pool/namespace
  ([user-management](https://docs.ceph.com/en/latest/rados/operations/user-management/)).
  Важно: cephx — аутентификация, а не шифрование; страница прямо перечисляет
  ограничения (plaintext keyring, отсутствие секретности по умолчанию) и добавляет,
  что «Ceph does not include options to encrypt user data in the object store».
- Прозрачность: объекты в BlueStore (RocksDB + BlueFS) — диск OSD на другом хосте
  не читается. FileStore — legacy; Red Hat помечает его как deprecated, а в апгрейде
  Quincy→Squid ожидается deprecation warning ([Squid release notes](https://docs.ceph.com/en/latest/releases/squid/)).
- iSCSI-шлюз Ceph официально **deprecated** в пользу NVMe-oF:
  «iSCSi support is now deprecated in favor of future NVMEoF support»
  ([Red Hat Ceph Storage 5.1 release notes](https://docs.redhat.com/en/documentation/red_hat_ceph_storage/5.1/html/release_notes/deprecated-functionality)).

#### GlusterFS

- Архитектура: brick = каталог-экспорт на сервере доверенного пула; типы томов —
  distributed, replicated, distributed-replicated, dispersed, distributed-dispersed;
  arbiter (replica 3) против split-brain ([Setting up Volumes](https://docs.gluster.org/en/latest/Administrator-Guide/Setting-Up-Volumes/)).
- Клиенты: FUSE (`mount -t glusterfs`), NFS-Ganesha, libgfapi; серверы —
  userspace `glusterd`/`glusterfsd`.
- Транспорт: «tcp is the default and currently only available transport» (в контексте
  создания тома).
- Разграничение доступа: `auth.allow`/`auth.reject`; права POSIX; квоты.
- Статус: Red Hat Gluster Storage — «defined support lifecycle through to 31-Dec-24»
  ([Red Hat Life Cycle](https://access.redhat.com/support/policy/updates/rhs)).
  Коммерческий продукт завершён; открытая разработка во многом держится сообществом.
- Прозрачность: данные — обычные файлы в brick'е; в этом смысле brick можно прочитать
  напрямую (иллюзия ФС строится над каталогом), но корректность томов и `.glusterfs`
  при этом ломается.

#### Lustre

- Официальное руководство — [doc.lustre.org](https://doc.lustre.org/lustre_manual.xhtml).
  Архитектура: MGS/MGT, MDT/MDS, OST/OSS, LNet (TCP или InfiniBand).
- ОС: Linux. Клиент исторически out-of-tree; попытка upstream'а клиента через staging
  закончилась изъятием, сегодня есть отдельный проект upstreaming
  ([wiki.lustre.org](https://wiki.lustre.org/Lustre_Upstreaming_to_Linux_Kernel)).
- Безопасность: GSS/Kerberos, nodemap, root squash (см. руководство). Шифрования
  транспорта «из коробки» нет.
- Backends: ldiskfs (вариант ext4) или ZFS. Данные — lobjects/OI, на другом хосте
  напрямую не читаются.
- HPC-ориентирован; для homelab избыточно.

#### BeeGFS

- Клиент — patchless kernel-модуль, серверы — userspace **демоны**; RDMA опционален,
  иначе TCP ([doc.beegfs.io](https://doc.beegfs.io/latest/advanced_topics/rdma_support.html)).
- Лицензирование — важный нюанс: BeeGFS 8 ввёл лицензии. Community-лицензия имеет
  лимит ёмкости (в BizDev-описании — 1200 ТБ: 1000 ТБ HDD + 200 ТБ SSD), Enterprise
  снимает лимиты и открывает quota/storage pools; без лицензии монтируются максимум
  5 клиентов ([licensing](https://doc.beegfs.io/latest/advanced_topics/licensing.html),
  [Enterprise Features](https://www.beegfs.io/c/enterprise-features/)).
- Разграничение доступа — общий `connAuthFile` (модель доверенного кластера);
  шифрования транспорта нативно нет.
- Прозрачность: chunk-файлы в storage targets; метаданные в БД — напрямую не читаются.
- Официальных цифр RAM/CPU в docs нет.

#### MooseFS

- Архитектура ([moosefs.com/architecture](https://moosefs.com/architecture.html)):
  «Master Servers hold the metadata ... Chunkservers store the data ... File data never
  flows through a Master Server»; репликация и erasure coding (Community — одна parity
  часть 4+1/8+1, Pro — до десяти).
- Community: один активный Master + Metalogger (восстановление вручную);
  Pro: несколько Master с автоматическим failover, Windows-клиент, multi-location.
- Лицензия: Community — GPLv2; Pro — проприетарный (там же).
- Прозрачность: чанки на chunkserver'ах, метаданные на Master — напрямую не читаются.
  Косвенная цифра накладных на мелкие файлы (из README SeaweedFS, цитирующего
  руководство MooseFS 3.0) — см. «Не подтверждённые утверждения».

#### JuiceFS

- Данные — чанки в object storage; метаданные — в Redis/MySQL/TiKV/SQLite и др.
  ([introduction](https://juicefs.com/docs/community/introduction/)); клиент — FUSE.
- Шифрование: at-rest, клиентское — «encrypts first, then uploads», гибридная схема
  (AES-256-GCM / ChaCha20-Poly1305 / SM4-GCM для данных + RSA-обёртка ключа);
  включается **только при создании** ФС; **клиентский кэш не шифруется**
  ([Data Encryption](https://juicefs.com/docs/community/security/encryption/)).
- Лицензия: Apache-2.0 (Community); в intro это указано явно. Есть отдельные
  Enterprise/Cloud версии.
- Официальные бенчмарки проект публикует (раздел Benchmark & Profiling в docs) —
  числа смотреть на странице проекта.

#### SeaweedFS

- Архитектура: master (Raft при 3 репликах), volume servers (append-only volume-файлы,
  16 байт индекса на blob), filer (метаданные в произвольном store), S3/WebDAV/SFTP/
  FUSE/HDFS (README).
- Метаданные: «40 bytes of metadata per file on disk», «no per-file inode, no per-file
  metadata file».
- Разграничение: S3 credentials/IAM/STS, JWT для доступа к volume, mTLS; шифрование
  at-rest AES256-GCM.
- Single-node: `weed mini` — «fine for single-node production» (например, S3-gateway).
- Официальные бенчмарки — в README (одна машина, 1M файлов по 1KB: 15 708 записей/с,
  47 019 чтений/с; микс S3 ~3.2 GiB/s). Это «unscientific single-machine numbers» по
  признанию самих авторов.

#### HDFS

- HA: NameNode HA с JournalNodes, Federation
  ([HdfsHighAvailability](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-hdfs/HdfsHighAvailability.html));
  блочная модель, репликация.
- Безопасность: в secure mode «each Hadoop service and each user must be authenticated
  by Kerberos»; шифрование RPC (`hadoop.rpc.protection=privacy`), шифрование передачи
  блоков (`dfs.encrypt.data.transfer`, AES/CTR), SASL на data transfer, HTTPS для UI;
  at-rest — Transparent Data Encryption ([SecureMode](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/SecureMode.html)).
- Разграничение: POSIX-like permissions model + ACL; KMS/TDE.
- Прозрачность: DataNode хранит блоки как файлы + `.meta` (checksums); NameNode — fsimage;
  напрямую на другой машине не читается.
- Официальных цифр RAM/CPU в docs нет. HDFS оптимизирован под большие файлы, слаб на
  множестве мелких.

#### LizardFS

- **Проект заброшен.** Репозиторий [lizardfs/lizardfs](https://github.com/lizardfs/lizardfs)
  — GPLv3; последний релиз 3.12.0 был ~9 лет назад. В issue #805
  ([«Is LizardFS development still alive?»](https://github.com/lizardfs/lizardfs/issues/805))
  заявлено: «we decided to not actively develop 3.x branch and go to LizardFS 5.x which
  is totally redesigned and rewritten». Windows-клиент вынесен на отдельную ссылку
  lizardfs.com (проприетарная история). **Не брать.**

#### XtreemFS

- Архитектура: DIR, MRC (metadata and replica catalog), OSD; клиент FUSE
  ([repo](https://github.com/xtreemfs/xtreemfs)). Лицензия: New BSD начиная с 1.3
  ([FAQ](https://www.xtreemfs.org/faq.php)).
- Безопасность: «XtreemFS uses unauthenticated and unencrypted TCP connections by
  default. To encrypt all network traffic, services and clients can establish SSL
  connections» ([Installation and User Guide](https://www.xtreemfs.org/xtfs-guide-1.2/index.html)).
- Проект малоактивен (последняя активность давняя) — в homelab не рекомендуется.

#### NFS-Ganesha

- Userspace NFS-сервер: «a user-mode file server for NFS v3, 4.0, 4.1, and 4.2»
  (текущий релиз — 6.5) ([wiki](https://github.com/nfs-ganesha/nfs-ganesha/wiki));
  pNFS поддерживается.
- FSAL-бэкенды ([Fsalsupport](https://github.com/nfs-ganesha/nfs-ganesha/wiki/Fsalsupport)):
  CEPH, GLUSTER, GPFS, PROXY_V3/V4, VFS, XFS, LUSTRE, RGW, KVSFS, LIZARDFS.
- Роль в homelab: единый NFS-фронт к Ceph/GlusterFS/Lustre (сам Ceph рекомендует
  NFS-Ganesha для CephFS — [CephFS NFS](https://docs.ceph.com/en/latest/cephfs/nfs/));
  на диске ничего нового не создаёт.

## Разграничение доступа

Ключевой водораздел — **блочные** протоколы (кто видит LUN, видит всё) против
**файловых/распределённых** (авторизация на уровне ФС/бэкенда).

- **iSCSI**: CHAP (односторонний/двусторонний), SRP, Kerberos; initiator/target ACL
  по имени IQN; шифрование — только IPsec; на уровне SCSI — «access control
  considerations» ([RFC 7143 §9.5](https://www.rfc-editor.org/rfc/rfc7143.txt)).
- **NVMe-oF**: DH-HMAC-CHAP (in-band) + TLS 1.3 для TCP ([NVM Express](https://nvmexpress.org/nvme-2-0-specifications-support-for-fabrics-and-multi-domain-subsystems/)).
- **FC/NVMe-FC/FCoE**: разграничение — zoning по WWPN, шифрования на уровне FC нет.
- **AoE**: аутентификации и шифрования **нет** вообще.
- **NBD**: TLS опционален; аутентификация не специфицирована.
- **DRBD**: аутентификация соединений через HMAC (mainline Kconfig требует
  `CRYPTO_HMAC`), шифрование трафика — TLS с 9.2.6.
- **Ceph**: cephx (аутентификация) + caps; шифрование — только msgr2 `secure`.
  Ceph явно предупреждает, что ключи лежат в plaintext-файлах, а human-user
  authentication не входит в cephx ([user-management](https://docs.ceph.com/en/latest/rados/operations/user-management/)).
- **GlusterFS**: `auth.allow`/`auth.reject` + POSIX-права + квоты; TLS опционален.
- **Lustre**: GSS/Kerberos, nodemap, root squash; права POSIX.
- **BeeGFS**: общий `connAuthFile` (модель доверенного кластера), прав POSIX/ACL;
  quotas — enterprise.
- **MooseFS**: `mfsexports.cfg` (сеть + права), в Pro — общий auth-код между модулями.
- **JuiceFS**: аутентификация — на движке метаданных и object storage; **клиентское
  шифрование at-rest** (AES-256-GCM и др.), но метаданные (имена, права) не шифруются.
- **SeaweedFS**: S3 IAM/STS/policies, JWT к volume, mTLS, AES256-GCM at rest.
- **HDFS**: Kerberos обязателен для secure mode, SASL, TDE, permissions/ACL.
- **OCFS2 / GFS2 / VMFS**: только POSIX-права (OCFS2 — ACL/xattr) и fencing;
  **шифрования транспорта нет**, предполагается физически доверенный SAN.

## Прозрачность на диске

Что физически лежит на носителе и что можно/нельзя прочитать в обход системы.

| Система | Что на носителе | Прочитать в обход? |
|---|---|---|
| iSCSI / NVMe-oF / FC / FCoE / AoE / NBD / SRP | Сырые блоки SCSI/NVMe/байты; никакой структуры у протокола | Да: любой, у кого есть доступ к LUN/экспорту, видит данные целиком (или снимает диск и монтирует локально, отключив LUN) |
| DRBD | Сырые блоки «нижнего» устройства + метаданные DRBD (bitmap, activity log) | Да, но только на узле, где ресурс в роли Primary (Secondary вообще не даёт чтения) |
| OCFS2 / GFS2 | Собственный on-disk формат кластерной ФС (+ журналы по узлам) | Монтируется только своим драйвером; обычными ФС-инструментами не читается. В VA (не для dual-primary) можно монтировать на одном узле |
| VMFS | Проприетарный формат VMware | Нет: вне ESXi не монтируется штатно |
| Ceph | Объекты в BlueStore: RocksDB + BlueFS на OSD | Нет: диск OSD на другом хосте не даёт файлов |
| GlusterFS | FUSE-том поверх обычных каталогов-brick'ов на XFS + служебный `.glusterfs` | **Да, частично**: файлы лежат как обычные файлы; но правка/монтирование в обход ломает корректность тома |
| Lustre | lobjects/OI на MDT/OST (ldiskfs или ZFS) | Нет: напрямую на другой машине не читается |
| BeeGFS | Chunk-файлы в storage targets; метаданные в БД | Нет |
| MooseFS | Чанки на chunkserver'ах; метаданные на Master | Нет |
| JuiceFS | Сжатые/зашифрованные объекты в bucket; метаданные в БД | Нет (без расшифровки/инструмента) |
| SeaweedFS | Append-only volume-файлы (`.dat` + `.idx`); контент маленьких файлов — единым блоком | Формат известен и разбираем, но это не «обычные файлы в ФС» |
| HDFS | Блоки + `.meta` на DataNode; fsimage на NameNode | Нет |
| XtreemFS | Объекты на OSD | Нет |
| NFS-Ganesha | Прокси — на диске только данные бэкенда | Зависит от бэкенда (CEPH/GLUSTER/…); сам Ganesha ничего не добавляет |

## Что НЕ стоит брать и почему

1. **OCFS2, GFS2, VMFS на 1–2 узлах.** Кластерная ФС без кластера бессмысленна и
   опасна: GFS2 требует кворума и fencing, OCFS2 — `o2cb` с disk-heartbeat и
   self-fencing. Для одного хоста это лишний слой, который ничего не даёт.
2. **LizardFS.** Заброшен: последний релиз ~2016, 3.x не развивается
   ([issue #805](https://github.com/lizardfs/lizardfs/issues/805)).
3. **AoE.** Нет аутентификации, нет шифрования, нет маршрутизации. Только доверенный
   L2-домен, и всё равно не даёт ничего поверх iSCSI/NVMe-oF.
4. **FCoE.** Официально deprecated/obsoleted у Broadcom (Fabric OS 9.2.2).
5. **FC, iSER, SRP, SMB Direct в homelab.** Требуют специального железа (HBA/RNIC/
   RoCE/IB); для 1–2 машин нерационально.
6. **Ceph/GlusterFS/Lustre/BeeGFS «в три узла ради одного диска».** Ceph single-host
   официально «not suitable for production»; RHGS завершён 31.12.2024; Lustre/BeeGFS —
   HPC-системы с лицензионными/аппаратными требованиями.
7. **DRBD dual-primary и любая обычная ФС на общем LUN.** Dual-primary требует
   кластерной ФС; ext4/XFS на одном LUN с двух хостов — путь к порче данных.
8. **Ожидать шифрования «по умолчанию» от распределённых ФС.** У Ceph по умолчанию
   `crc` (без секретности), у Lustre/BeeGFS/MooseFS/GlusterFS шифрования транспорта
   нативно нет, у OCFS2/GFS2 — нет в принципе.

## Не подтверждённые утверждения

- **Официальных цифр пропускной способности/RAM** для iSCSI, iSER, NVMe-oF, FC, FCoE,
  AoE, NBD, SRP, SMB Direct не найдено — в таблицах только архитектурные признаки.
- **Точная версия ядра Linux**, в которой появился `nvme-tcp`, официальной документацией
  не подтверждена (в kernel docs версия не указана). Косвенно — патч-
  серия Sagi Grimberg в списке рассылки NVMe; это не официальный релиз-ноут.
- **Mainline DRBD = «8.4»**: Kconfig версии не называет; привязку «8.4 к mainline»
  даёт LINBIT (отдельное руководство для 8.4), а не сам код.
- **Порт DRBD по умолчанию (7788)** в этом обзоре не подтверждён первоисточником и не
  приводится.
- **macOS/BSD iSCSI-инитор**: встроенного инитиатора в macOS нет; сторонние решения
  (globalSAN и т. п.) не проверялись по вендорской документации. Наличие встроенного
  iSCSI в FreeBSD не проверялось.
- **Наличие/отсутствие Windows-клиентов** для GlusterFS/BeeGFS: в официальных docs
  подтверждения «поддерживается» не найдено; для BeeGFS — Windows-клиент в доке не
  заявлен как поддерживаемый (формулировка «не подтверждено»).
- **Накладные MooseFS на мелкие файлы** (64 KiB + checksums + header) — цифра
  встречается в README SeaweedFS со ссылкой на руководство MooseFS 3.0; из
  первоисточника MooseFS в этом обзоре не подтверждена.
- **Удаление FileStore в upstream Ceph**: точной цитаты из release notes о *removal*
  не найдено; подтверждено, что FileStore — legacy/deprecated (Red Hat, апгрейд
  Quincy→Squid даёт deprecation warning).
- **Точные версии/даты вывода VMFS-3** и специфики VMFS-6 по официальной документации
  VMware/Broadcom в этом проходе не подтверждены.
- **Точные имена опций TLS** в GlusterFS (`glusterfs.ssl` и т. п.) и полный список
  параметров `connAuthFile` BeeGFS — по сводным страницам, не по одному RFC/ману.
- **Официальные бенчмарки Lustre, GlusterFS, MooseFS, HDFS, XtreemFS** на их
  документационных сайтах не найдены.
- **Kernel-документация GFS2** на docs.kernel.org по прямым путям не открылась;
  используется документация Red Hat.

## Основные источники

- iSCSI: [RFC 7143](https://www.rfc-editor.org/rfc/rfc7143.txt);
  [TCM Virtual Device](https://www.kernel.org/doc/html/latest/target/index.html);
  [open-iscsi](https://github.com/open-iscsi/open-iscsi)
- iSER: [RFC 7145](https://www.rfc-editor.org/rfc/rfc7145.txt)
- SRP: [RFC 5046](https://www.rfc-editor.org/rfc/rfc5046.txt)
- NVMe-oF: [NVMe 2.0 / Fabrics](https://nvmexpress.org/nvme-2-0-specifications-support-for-fabrics-and-multi-domain-subsystems/);
  [NVMe Subsystem (kernel docs)](https://docs.kernel.org/nvme/index.html);
  [NVMe-oF spec PDF](https://nvmexpress.org/wp-content/uploads/NVMe-over-Fabrics-1.1a-2021.07.12-Ratified.pdf)
- Fibre Channel / FCoE: [INCITS T11](https://www.incits.org/committees/t11);
  [Broadcom FCoE deprecation](https://techdocs.broadcom.com/us/en/fibre-channel-networking/fabric-os/fabric-os-administration/9-2-x/understanding-fcoe-92x-admin.html)
- AoE: [Kernel AoE docs](https://docs.kernel.org/5.16/admin-guide/aoe/index.html);
  [drivers/block/aoe/aoe.h](https://github.com/torvalds/linux/blob/master/drivers/block/aoe/aoe.h)
- NBD: [Kernel NBD](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/nbd.html);
  [proto.md](https://github.com/NetworkBlockDevice/nbd/blob/master/doc/proto.md)
- SMB Direct: [Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-direct)
- DRBD: [DRBD 9 User Guide](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/);
  [mainline Kconfig](https://github.com/torvalds/linux/blob/master/drivers/block/drbd/Kconfig)
- OCFS2: [kernel docs](https://docs.kernel.org/filesystems/ocfs2.html);
  [o2cb(7)](https://manpages.debian.org/testing/ocfs2-tools/o2cb.7.en.html);
  [Oracle OCFS2](https://docs.oracle.com/en/operating-systems/oracle-linux/9/ocfs2/OL9-OCFS2.pdf)
- GFS2: [RHEL 9 GFS2 in a cluster](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_high_availability_clusters/assembly_configuring-gfs2-in-a-cluster-configuring-and-managing-high-availability-clusters)
- VMFS: [Broadcom vSphere VMFS Datastores](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-storage/working-with-datastores-in-vsphere-storage-environment/vsphere-vmfs-datastore-concepts-and-operations.html)
- Ceph: [minimum hardware](https://docs.ceph.com/en/latest/start/minimum-hardware/);
  [CPU/memory](https://docs.ceph.com/en/latest/start/hardware-cpu-memory/);
  [msgr2](https://docs.ceph.com/en/latest/rados/configuration/msgr2/);
  [user management](https://docs.ceph.com/en/latest/rados/operations/user-management/);
  [cephadm install](https://docs.ceph.com/en/latest/cephadm/install/);
  [CephFS NFS](https://docs.ceph.com/en/latest/cephfs/nfs/);
  [Red Hat Ceph 5.1 deprecated functionality](https://docs.redhat.com/en/documentation/red_hat_ceph_storage/5.1/html/release_notes/deprecated-functionality)
- GlusterFS: [docs.gluster.org](https://docs.gluster.org/en/latest/Administrator-Guide/Setting-Up-Volumes/);
  [Red Hat Gluster Storage Life Cycle](https://access.redhat.com/support/policy/updates/rhs)
- Lustre: [doc.lustre.org](https://doc.lustre.org/lustre_manual.xhtml);
  [Upstreaming wiki](https://wiki.lustre.org/Lustre_Upstreaming_to_Linux_Kernel)
- BeeGFS: [licensing](https://doc.beegfs.io/latest/advanced_topics/licensing.html);
  [RDMA support](https://doc.beegfs.io/latest/advanced_topics/rdma_support.html);
  [Enterprise features](https://www.beegfs.io/c/enterprise-features/)
- MooseFS: [architecture](https://moosefs.com/architecture.html);
  [GitHub](https://github.com/moosefs/moosefs)
- JuiceFS: [introduction](https://juicefs.com/docs/community/introduction/);
  [encryption](https://juicefs.com/docs/community/security/encryption/)
- SeaweedFS: [README](https://github.com/seaweedfs/seaweedfs)
- HDFS: [Secure Mode](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/SecureMode.html);
  [High Availability](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-hdfs/HdfsHighAvailability.html)
- LizardFS: [repo](https://github.com/lizardfs/lizardfs);
  [issue #805](https://github.com/lizardfs/lizardfs/issues/805)
- XtreemFS: [repo](https://github.com/xtreemfs/xtreemfs);
  [FAQ](https://www.xtreemfs.org/faq.php);
  [Installation and User Guide](https://www.xtreemfs.org/xtfs-guide-1.2/index.html)
- NFS-Ganesha: [wiki](https://github.com/nfs-ganesha/nfs-ganesha/wiki);
  [FSAL support](https://github.com/nfs-ganesha/nfs-ganesha/wiki/Fsalsupport)
