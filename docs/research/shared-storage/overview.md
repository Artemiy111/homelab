# Протоколы разделяемого (сетевого) хранилища: обзор и сводка

Дата проверки: 2026-10-13.

## Состав документа

Тема разложена на три главы по уровню доступа к данным; этот файл — входная
точка: категории, сводные таблицы по осям, сквозной разбор разграничения
доступа и прозрачности на диске, выводы для homelab.

| Глава | Что внутри |
|---|---|
| [`file-level-protocols.md`](file-level-protocols.md) | SMB 2/3, NFS v2/v3/v4.0/4.1/4.2, AFP, WebDAV, FTP/FTPS, SFTP/SSHFS, 9P, virtiofs, NBD, rsync-daemon, davfs2, rclone |
| [`block-and-cluster.md`](block-and-cluster.md) | iSCSI, iSER, NVMe-oF, Fibre Channel, FCoE, AoE, SRP, NBD, DRBD, OCFS2, GFS2, VMFS, Ceph, GlusterFS, Lustre, BeeGFS, MooseFS, JuiceFS, SeaweedFS, HDFS, XtreemFS, LizardFS, NFS-Ganesha |
| [`object-storage-and-cloud-drives.md`](object-storage-and-cloud-drives.md) | S3, Swift, Azure Blob, GCS, CDMI, self-hosted S3-реализации, «S3 как ФС», Nextcloud, oCIS/OpenCloud, Seafile, Pydio, Syncthing, rsync/rclone/Unison |

Метод: каждое утверждение в главах привязано к первоисточнику — RFC,
спецификации Microsoft/Apple/NVMe, официальная документация проекта,
man-страницы, исходный код. Где официальных цифр нет — это написано прямо, а не
заменено оценкой. Опорные факты глав (цифры Ceph и DRBD, статус MinIO, цитаты
Nextcloud про primary object storage) перепроверены отдельно при сведении.

## Зачем это нужно

В homelab одновременно живут четыре разных решения для «сетевого диска»:
Samba (SMB), Nextcloud, Seafile и RustFS. Это не альтернативы друг другу — они
из разных категорий, и разные категории отвечают на разные вопросы. Документ
раскладывает всё поле по категориям и сжимает каждое решение до набора
параметров, которые реально влияют на выбор:

1. **Поддержка ОС** — какие клиенты есть «из коробки», что требует пакета, что
   недоступно без родного клиента.
2. **Потребление ресурсов** — ядро или userspace, сколько процессов, где
   копируются данные, официальные требования к RAM/CPU.
3. **Разграничение доступа** — аутентификация и авторизация: что несёт сам
   протокол, а что является надстройкой (LDAP/AD/OIDC, ACL, доли, ссылки).
4. **Прозрачность на диске** — можно ли править содержимое носителя напрямую,
   локально, и увидеть это через сеть. Это главная ось документа: она разводит
   «папка на диске» и «сервис со своей базой».
5. Транспорт и порты, шифрование, производительность, HA/масштаб, статус.

## Категории: на каком уровне протокол отдаёт данные

| Уровень | Единица доступа | Что видит клиент | Примеры |
|---|---|---|---|
| Файловый | файл | дерево каталогов | SMB, NFS, WebDAV, SFTP/SSHFS, 9P, virtiofs, AFP |
| Блочный | сектор | «сырой» диск `/dev/sdX` | iSCSI, iSER, NVMe-oF, Fibre Channel, FCoE, AoE, NBD, SRP, DRBD |
| Объектный | объект в бакете | плоское пространство ключей | S3, Swift, Azure Blob, GCS, CDMI |
| Кластерная/распределённая ФС | файл | дерево, общее для многих узлов | CephFS, GlusterFS, Lustre, BeeGFS, MooseFS, JuiceFS, SeaweedFS, HDFS, OCFS2, GFS2 |
| Прикладной слой | файл/ссылка | UI, синхронизация, шеринг | Nextcloud, Seafile, oCIS, Pydio, Syncthing |

Ключевое различие, которое чаще всего путают: **протокол** и **реализация**.
SMB — протокол, Samba — его реализация. S3 — протокол, RustFS — реализация.
Nextcloud отдаёт наружу WebDAV, но WebDAV не является хранилищем. Поэтому
«прозрачность на диске» определяется не именем протокола, а тем, как
реализация складывает байты: NFS и SMB-поверх-локальной-ФС прозрачны, а
Seafile/Nextcloud-с-object-store — нет, хотя наружу и то и другое умеет WebDAV.

## Текущий стенд (снимок на 2026-10-19)

| Сервис | Категория | Что отдаёт наружу | Где лежат данные | Прозрачность на диске |
|---|---|---|---|---|
| Samba (`apps/casa/samba`) | файловый | SMB2.1+ (порт 445), одна шара: `ntfs1` rw | том внешнего NTFS-диска, смонтированный на хосте (`ntfs3`), в под попадает как `hostPath` | **полная**: файлы лежат на NTFS как есть, изменение локально видно по SMB |
| Nextcloud (`apps/casa/nextcloud`) | прикладной | WebDAV + web-UI, только LAN/Tailscale | PVC `nextcloud-html` (Longhorn, RWO, 2 Gi): код, `config.php`, пользовательские файлы; индекс и метаданные — PostgreSQL в общем кластере CNPG; Redis для кеша, сессий и блокировок файлов | **частичная**: файлы в data-каталоге лежат как есть, но индекс, доли и блокировки живут в БД — правка в обход приложения рассинхронизирует индекс |
| Seafile (`apps/casa/seafile`) | прикладной | WebDAV (`seafdav`) + web-UI, SSO через Zitadel (OIDC), OnlyOffice | PVC `seafile-shared` (Longhorn, RWO, 64 Mi): блоки данных и метаданные; библиотеки — MariaDB (`ccnet_db`, `seafile_db`, `seahub_db` под mariadb-operator) | **нет**: содержимое разложено по блокам (CDC ~8 МБ), библиотека собирается из БД |
| RustFS (`apps/casa/rustfs`) | объектный | S3 API (`https://s3.<домен>`) + веб-консоль | PVC `rustfs-data` (Longhorn, RWO, 2 Gi), режим single-node single-disk: без erasure coding и избыточности | **нет**: объекты в собственном формате; только root-креденшелы, IAM-пользователей нет |

Что из этого следует:

- Samba даёт то, чего не дадут три остальных: файлы правит кто угодно и чем
  угодно, включая сам сервер. Плата — разграничение доступа упирается в одну
  локальную учётку `storage` (`valid users = storage` на шаре) и
  `force user = ops`: на диске все записи принадлежат `ops`, per-user ACL
  нет, Kerberos/AD в homelab нет. Это не ошибка конфигурации, а осознанный
  компромисс — но именно он ограничивает шару одним «владельцем».
- Nextcloud и Seafile — не хранилища, а приложения поверх хранилища: их
  ценность в шеринге, истории версий, офисных интеграциях и SSO, а не в
  скорости файловых операций.
- RustFS — не «диск», а S3-эндпоинт: к нему обращаются приложения, а не
  Проводник.

## Сводные таблицы по категориям

### Файловые протоколы

| Протокол | Клиенты/ОС | Data-path | Что несёт протокол по доступу | Прозрачность на диске |
|---|---|---|---|---|
| SMB 2/3 (Samba, Windows, `ksmbd`) | Windows, macOS, Linux (`cifs.ko`), FreeBSD (только SMB1), iOS Files.app | сервер Samba — userspace (процесс на сессию); Windows/`ksmbd` — ядро | NTLM/NTLMv2, Kerberos (SPNEGO), security descriptors (SID, DACL/SACL); LDAP/AD — надстройка (winbind) | файлы как есть, но NT ACL → xattr `security.NTACL`, ADS → `user.DosStream.*` (лимит xattr ~4К), либо ACL в TDB |
| NFSv3 | Linux (ядро), Windows Client for NFS, macOS, BSD | ядро-ядро | AUTH_SYS (uid/gid), `root_squash`; NFSACL — нестандартное расширение Solaris | полная: pass-through в VFS, своего хранилища метаданных нет |
| NFSv4.0/4.1/4.2 | Linux, Windows Server for NFS (v4.1), macOS (до 4.1), FreeBSD | ядро-ядро | обязателен RPCSEC_GSS: krb5/krb5i (MUST), krb5p (MUST у сервера); NFSv4 ACL с трансляцией в POSIX ACL; RPC-with-TLS | полная, с оговорками: `root_squash` → uid 65534, делегирования ограничивают локальный доступ |
| WebDAV | любой HTTP-клиент, `davfs2`, Finder, Windows redirector | HTTP-стек или приложение | Digest обязателен, Basic только поверх TLS; `DAV:acl` (RFC 3744) опционален; OIDC/SSO — целиком надстройка | частичная: dead properties и блокировки живут в БД/индексе сервера, а не в файле |
| FTP/FTPS | массовые клиенты, IIS, `vsftpd` | userspace | USER/PASS (открытым текстом в базовом RFC), AUTH TLS | полная по данным, но у протокола нет модели атрибутов (нет ACL/xattr/владельца) |
| SFTP/SSHFS | любые SSH-клиенты, sshfs (FUSE) | userspace | SSH-ключи/пароль/GSSAPI; `ChrootDirectory`, `sftp-server -R/-P` | полная; отдаёт только mode/uid/gid, без xattr/ACL |
| 9P / 9P2000.L | Linux (`v9fs`), WSL1, Plan 9 | ядерный клиент + userspace сервер (diod) | в протоколе `auth` есть, но его содержимое не определено; diod — MUNGE или `--no-auth` | полная, но нет инвалидации кэша на клиенте; шифрования нет |
| virtiofs | гость Linux 5.4+, macOS-гость (Virtualization.framework) | virtqueue, сети нет | аутентификации нет по построению; `virtiofsd` изолируется seccomp/namespaces; ACL/SELinux не экспонируются по умолчанию | полная: экспортируется хостовый каталог как есть |
| AFP (Netatalk) | macOS (клиент вырезается), Linux/BSD-сервер | userspace | UAM-модули (SRP), AppleShare-права → POSIX; AFP-ACL 3.x частично | частичная: resource forks/FinderInfo и CNID хранятся вне файла |
| rsync-daemon | любые | userspace | MD4 challenge-response, шифрования нет (только ssh-туннель) | не ФС — это синхронизация файлов «как есть» |
| NBD | Linux-клиент (ядро), `nbd-server`/`nbdkit` | ядерный клиент + userspace сервер | аутентификации не специфицировано, TLS опционален | блочное устройство: ФС внутри видна только после монтирования |

### Блочные протоколы

| Протокол | Клиенты/ОС | Data-path | Что несёт протокол по доступу | Прозрачность на диске |
|---|---|---|---|---|
| iSCSI | Linux, Windows, VMware, сторонние initiator'ы | initiator в ядре, target LIO в ядре | CHAP/SRP/Kerberos, ACL по IQN, шифрование — только IPsec | сырой LUN: кто видит устройство — видит все данные целиком |
| iSER / SRP | Linux + RDMA-железо | ядро | наследует iSCSI / IB-модель | сырой блок |
| NVMe-oF (TCP/RDMA/FC) | Linux, Windows, VMware | ядро | DH-HMAC-CHAP in-band, TLS 1.3 для TCP; FC — zoning по WWPN | сырой блок |
| Fibre Channel / FCoE | HBA + свитч | HBA + драйвер | zoning по WWPN; шифрования нет; **FCoE официально deprecated** у Broadcom | сырой блок |
| AoE | Linux-клиент (модуль ядра) | ядро | **аутентификации и шифрования нет**, только один L2-домен | сырой блок |
| DRBD | Linux + (с 9.2.0) RDMA | ядро + userspace-утилиты | аутентификация HMAC, шифрование TLS с 9.2.6 | зеркало блочного устройства; читается только на Primary |
| SMB Direct | Windows Server, client-only на Windows 10/11 | RDMA | наследует SMB (шифрование SMB3 с WinSrv2022/Win11) | шара SMB, не блочное устройство |

### Кластерные и распределённые ФС

| Система | Клиенты/ОС | Узлы | Что несёт по доступу | Прозрачность на диске |
|---|---|---|---|---|
| OCFS2 | Linux (in-tree) | ≥2 узла на одном LUN, `o2cb` + disk-heartbeat + self-fencing | POSIX-права, ACL/xattr; шифрования транспорта нет | свой формат: чужими ФС-инструментами не читается |
| GFS2 | Linux (RHEL/community) | ≥2 узла, требуется кворум, DLM + fencing | POSIX/ACL/квоты; шифрование только LUKS-слоем | свой формат |
| VMFS | только VMware ESXi | ESXi-хосты + общий LUN | аутентификация vSphere | проприетарный формат, вне ESXi не монтируется |
| Ceph (RBD/CephFS/RADOS) | Linux (ядро/FUSE), Windows (`ceph-dokan`), BSD | официально ≥3 mon; single-host «generally not suitable for production» | cephx (аутентификация) + caps; шифрование только в режиме msgr2 `secure`; по умолчанию `crc` | BlueStore (RocksDB + BlueFS): диск OSD на другом хосте не даёт файлов |
| GlusterFS | Linux (FUSE/ganesha/libgfapi) | brick на любом числе узлов, арбитр требует ≥3 | `auth.allow/auth.reject`, POSIX-права, опциональный TLS | частично: brick — обычный каталог, но правка в обход ломает том |
| Lustre | Linux (клиент out-of-tree) | MGS/MDT/OST, несколько узлов | GSS/Kerberos, nodemap, root squash; шифрования транспорта нет | lobjects/OI: напрямую не читается |
| BeeGFS | Linux | management + storage targets | общий `connAuthFile`; шифрования нет; Community-лицензия с лимитом 1200 ТБ | chunk-файлы: напрямую не читается |
| MooseFS | Linux, BSD, macOS (Windows только в Pro) | 1 Master + chunkservers | `mfsexports.cfg`; в Pro — общий auth-код | чанки: напрямую не читается |
| JuiceFS | Linux, macOS, Windows (WinFsp) | 1 узел возможен (SQLite); HA — внешний движок метаданных | аутентификация движка метаданных и object storage; клиентское шифрование at-rest | чанки + **обязательная внешняя БД метаданных**: без неё файлы в бакете нечитаемы |
| SeaweedFS | Linux, macOS, Windows | `weed mini` годится для single-node production | S3 IAM/STS/policies, JWT, mTLS, AES256-GCM at rest | append-only `.dat`/`.idx` — формат известен, но это не «файлы в ФС» |
| HDFS | Linux/Windows/macOS (Java), FUSE сторонний | NameNode + DataNodes | в secure mode Kerberos обязателен, SASL, TDE | блоки + `.meta`: напрямую не читается |
| XtreemFS / LizardFS | — | — | XtreemFS по умолчанию **без** аутентификации и шифрования; LizardFS заброшен (~2016) | объекты/чанки: не читается |
| NFS-Ganesha | Linux, FreeBSD (VFS FSAL) | userspace-демон | Kerberos, NFSv4 ACL, делегирование бэкенду | прокси: на диске ничего не добавляет |

### Объектные протоколы и «облачные диски»

| Решение | Клиенты/ОС | Data-path | Что несёт по доступу | Прозрачность на диске |
|---|---|---|---|---|
| S3 REST | любой HTTP/S3 SDK, AWS CLI | HTTP | SigV4, IAM/bucket policy (ACL по умолчанию отключены, `Bucket owner enforced`), pre-signed URL (bearer), Object Lock (governance/compliance) | объекты, а не файлы; in-place правки нет — только PUT объекта или multipart |
| OpenStack Swift | HTTP/SDK/CLI | HTTP | container ACL (`X-Container-Read/Write`), temp URL | объекты; сегменты SLO/DLO |
| Azure Blob | HTTP/SDK/CLI | HTTP | SAS (user delegation/service/account), immutability policy | block/append blob — только целиком; page blob — in-place запись 512 Б (исключение из объектной модели) |
| GCS | HTTP/SDK/CLI | HTTP | signed URL V4, IAM, Bucket Lock/object holds | объекты + версии (`generation`) |
| CDMI | HTTP | — | описан в самом стандарте (SNIA, ISO/IEC 17826) | не про скорость: discovery, provisioning, portability |
| RustFS / Garage / Ceph RGW / SeaweedFS S3 / Zenko / lakeFS | HTTP/S3 SDK | userspace | S3-модель (IAM/STS у части реализаций), OIDC у RustFS, LDAP/Keystone у RGW | объекты в собственном формате реализации |
| s3fs-fuse | Linux/macOS/FreeBSD | FUSE | креды бэкенда | **максимум прозрачности среди FUSE-надстроек**: «native object format», объект читается AWS CLI; плата — нет атомарного rename, случайная запись = перезапись объекта |
| Mountpoint for Amazon S3 | Linux | FUSE | AWS IAM | нативные объекты, но официально нет rename каталогов, symlink и правки файлов |
| goofys / GeeseFS / rclone mount | Linux/macOS/Windows | FUSE | креды бэкенда | синтезируют POSIX-атрибуты; goofys называет себя «Filey System» |
| Nextcloud | Web/desktop/iOS/Android | PHP + БД | share-ссылки, группы/роли, OIDC/SAML/LDAP, SSE (сервер расшифровывает) vs E2EE (только клиент) | файлы «как есть» + индекс в БД; при primary object storage контент в бакете только «by unique identifier» — вне Nextcloud не читается |
| oCIS / OpenCloud | Web/desktop | Go-микросервисы | встроенный IdP + внешние | `decomposedfs` — «not easily human readable»; `posix`-драйвер требует уведомления об изменениях (inotify) и **experimental** |
| Seafile | Web/desktop/SeaDrive | Python + БД + объекты | SSO (OIDC), библиотеки, E2EE (шифрованные библиотеки) | файлов «как есть» нет: объекты Commit/FS/Block, CDC ~8 МБ, дедуп |
| Pydio Cells | Web/desktop/API | Go-микросервисы | БД + ACL; SSO/LDAP — Enterprise | зависит от формата datasource: Structured — читаемо, Flat — нет |
| Syncthing | Linux/macOS/Windows | P2P (BEP), TLS 1.3 | device ID = SHA-256 сертификата, папки/устройства | файлы «как есть» + index-БД + `.stversions`; правка мимо — подхватится сканером |
| Resilio Sync | Win/mac/Linux | P2P, проприетарный ZGT | проприетарная | файлы + БД агента; wire-формат не публикуется |
| rsync / rclone sync / Unison | любые | userspace | SSH или MD4-челлендж / креды бэкенда | синхронизация «как есть», не общая ФС |

## Сквозная ось 1: прозрачность на диске

Главный вывод, который стоит запомнить: **чем прозрачнее хранилище на диске,
тем меньше оно умеет; чем богаче функции, тем сильнее данные зависят от БД,
индекса или клиента, который шифрует контент.**

Три градации:

- **Прозрачно (файлы — это и есть данные):** NFS, 9P, virtiofs, SFTP/FTP/rsync,
  локальная ФС под SMB (при оговорках ниже), GlusterFS-brick (с оговоркой).
  Локальная правка видна по сети; отдельного хранилища метаданных нет.
- **Частично (данные прозрачны, метаданные — нет):** SMB (NT ACL → xattr
  `security.NTACL`, ADS → `user.DosStream.*`, либо ACL в TDB), WebDAV (dead
  properties и локи в БД сервера), AFP (resource forks/CNID), Nextcloud с
  локальной ФС (индекс в БД; правка мимо требует пересканирования), Syncthing
  (index-БД, но сканер сам находит изменения).
- **Непрозрачно (на диске нет файлов):** Seafile, oCIS `decomposedfs`, JuiceFS,
  Ceph/CephFS, Lustre, BeeGFS, MooseFS, HDFS, XtreemFS, любой S3-бэкенд.
  Диск нельзя «прочитать» другим инструментом, а иногда — даже вынуть и
  смонтировать на другой машине.

Отдельно: прозрачность не бесплатна и в другую сторону. У Samba persistent
handles (4.25, эксперимент) требуют `kernel oplocks = no`, `kernel share modes =
no`, `posix locking = no`, и в release notes прямо сказано, что это «disables
interoperability with local POSIX file access and NFS clients on the affected
share». То есть попытка получить «и SMB, и локальный доступ, и хендлы» упирается
в выбор.

## Сквозная ось 2: разграничение доступа

| Модель | Кто её несёт | Где живёт состояние | Аутентификация |
|---|---|---|---|
| POSIX (uid/gid + mode bits) | NFSv2/v3, 9P, SFTP, FTP, rsync | inode в ФС сервера | AUTH_SYS (uid/gid); у FTP/9P протокольной аутентификации фактически нет |
| POSIX ACL | NFSv3 (частично), NFSv4 (трансляция), Samba (маппинг) | xattr `system.posix_acl_*` | как выше |
| NFSv4 ACL | NFSv4.0/4.1/4.2 | атрибут ФС либо трансляция в POSIX ACL | обязателен RPCSEC_GSS (krb5/krb5i/krb5p) |
| SMB security descriptor (SID, DACL/SACL) | SMB2/3 | xattr `security.NTACL` (Samba `acl_xattr`) или TDB | NTLM/NTLMv2, Kerberos, guest |
| Объектные политики | S3/Swift/Azure/GCS | бакет/контейнер + IAM | SigV4 / SAS / signed URL (bearer-токены) |
| Share-ссылки, группы, роли | приложения («облачные диски») | БД приложения | OIDC/SAML/LDAP — надстройка приложения, не протокола хранения |

Практические следствия:

- **Протокол vs надстройка.** SMB *несёт* SID/DACL/SACL и Kerberos-билеты, но
  LDAP/AD-интеграция — надстройка (winbind), без которой доменной модели нет.
  NFSv4 *несёт* flavor и принципала; каталог имён (`user@domain`) — idmap.
  WebDAV *несёт* только HTTP-аутентификацию; OIDC — целиком надстройка.
- **Блочные протоколы — не про права.** Кто видит LUN, видит все данные: iSCSI
  даёт CHAP/Kerberos и IPsec, NVMe-oF — DH-HMAC-CHAP и TLS, а FC/AoE — только
  zoning (или ничего). Права на файлы появляются лишь на слое ФС поверх LUN, и
  то если ФС кластерная.
- **E2EE ломает серверную модель доступа by design.** У Nextcloud: E2EE-файлы из
  веба только читаются/скачиваются, чанковые загрузки надо отключать, мнемонику
  администратор не восстановит, серверный поиск/превью/совместная работа
  деградируют. Это не баг, а граница модели угроз.
- **Bearer-токены утекают вместе с правами.** Pre-signed URL (S3), SAS (Azure),
  signed URL (GCS), temp URL (Swift) действуют от имени подписавшего; генерацию
  SAS в Azure вообще нельзя аудировать.

## Сквозная ось 3: потребление ресурсов

Официальных цифр почти нигде нет — это не пробел исследования, а свойство
документации проектов. Что удалось подтвердить первоисточником:

| Что | Цифра | Источник |
|---|---|---|
| Ceph | OSD ≥4 GiB RAM (default `osd_memory_target`), mon 2 cores + ≥5 GB, MDS 2 cores + ≥8 GiB | docs.ceph.com, minimum-hardware |
| Ceph, single-host | `--single-host-defaults`: «generally not suitable for production» | cephadm install |
| DRBD | ~32 MiB RAM на 1 TiB при битмапе 4 KiB/бит; максимум 1 PiB; ≤32 узла, >5 не рекомендуется | DRBD 9 User Guide, §1.5 |
| NFS LOCALIO | fio-замеры авторов патча: 128K read 49.1 GiB/s против 4.2 GiB/s без LOCALIO | docs.kernel.org, NFS LOCALIO |
| SeaweedFS | собственные single-machine бенчмарки в README (авторы сами называют их «unscientific») | README репозитория |
| BeeGFS | Community-лицензия с лимитом 1200 ТБ, без лицензии — не более 5 клиентов | doc.beegfs.io, licensing |

Всё остальное — архитектурные признаки, которые и определяют цену:
ядро-ядро (NFS) против userspace-процесса-на-сессию (Samba `smbd`), обязательный
локальный кэш (davfs2) против FUSE-прослойки (SSHFS, rclone), один round-trip на
операцию (SFTP, WebDAV) против COMPOUND/делегирований (NFSv4, SMB2+).

## Что осмысленно в homelab, а что нет

**Осмысленно:**

- SMB (Samba) — как «второй диск», который виден Windows/macOS/Linux одинаково.
  Оговорка: NT ACL уедут в xattr, а per-user ACL требует identity-модели
  (AD/winbind или хотя бы несколько Unix-учёток вместо одной `storage`).
- NFSv4 — как точки монтирования для Linux-контейнеров и сервисов, если нужен
  pass-through в локальную ФС без своего хранилища метаданных. Для доменной
  аутентификации — RPCSEC_GSS, для шифрования — `xprtsec=tls` или `sec=krb5p`.
- iSCSI/NVMe-oF — если действительно нужен блочный диск (образ ВМ, свой LVM).
  Помнить: два писателя по обычной (не кластерной) ФС — порча данных.
- DRBD — зеркало HA между двумя хостами, single-primary + любая обычная ФС.
- JuiceFS / SeaweedFS / MooseFS Community — «лёгкие» распределённые варианты в
  single-node/2-node режиме, если нужен общий namespace.
- Прикладной слой (Nextcloud, Seafile) — ради шеринга, версий, SSO и офисных
  интеграций, а не ради скорости файловых операций.
- Объектный слой (RustFS, Garage, Ceph RGW, SeaweedFS S3) — для приложений,
  которые говорят на S3, и для WORM/retention.

**Не осмысленно:**

- OCFS2/GFS2/VMFS на 1–2 узлах: кластерная ФС без кластера — лишний слой,
  который ничего не даёт и требует fencing/кворума.
- Ceph/GlusterFS/Lustre/BeeGFS «в три узла ради одного диска»: Ceph single-host
  официально «not suitable for production», RHGS завершён 31.12.2024,
  Lustre/BeeGFS — HPC-системы.
- LizardFS (заброшен), AoE (нет аутентификации и шифрования, нет маршрутизации),
  FCoE (deprecated у Broadcom), FC/iSER/SRP/SMB Direct (нужно специальное
  железо).
- Надеяться на «шифрование по умолчанию»: у Ceph по умолчанию `crc` без
  секретности, у Lustre/BeeGFS/MooseFS/GlusterFS/OCFS2/GFS2 шифрования
  транспорта нет. И это уже не «нет цифр» — это отсутствие механизма.
- Монтировать S3 как рабочий диск: s3fs/goofys/Mountpoint официально теряют
  rename, symlink, правку файлов и координацию между клиентами.

**Про WAN отдельно.** Файловые протоколы общего назначения (SMB, NFS, 9P) и
блочные — LAN-технологии: случайные порты (NFS sideband), отсутствие шифрования
в базовом протоколе, чувствительность к задержке и разрывам. По сети «через
интернет» спроектированы только HTTP(S)-семейство (WebDAV, S3), SFTP, SMB over
QUIC и синхронизация (Syncthing, rclone, rsync-over-ssh). Это ровно то, что
видно в этом homelab: SMB-скорость ~800 КБ/с упирается в канал, и ускорять её
правильно не тюнингом Samba, а сменой модели доступа на HTTP/синхронизацию.

## Выводы

1. Категория важнее продукта: «сетевое хранилище» — это пять разных уровней, и
   выбор протокола определяется тем, нужна ли блочная семантика, POSIX-семантика,
   объектная модель или прикладной шеринг.
2. Прозрачность на диске — самая недооценённая ось. Она решает, можно ли будет
   достать данные без сервиса, сделает ли бэкап обычный `rsync`, переживёт ли
   система потерю БД. Seafile/JuiceFS/Nextcloud-с-object-store — нет; NFS/SMB/
   9P/virtiofs — да.
3. Чем больше функций (версии, дедуп, шеринг, E2EE), тем меньше шансов, что
   данные на диске читаемы посторонним инструментом. Обратное тоже верно.
4. Разграничение доступа почти всегда упирается не в протокол, а в
   identity-модель: протоколы умеют Kerberos/NFSv4 ACL/SID, но без KDC/LDAP/
   AD-надстройки в homelab остаётся одна-две Unix-учётки.
5. Блочные протоколы — только для честного блочного диска и только с одним
   писателем (или с кластерной ФС).
6. Все «распределённые» технологии (Ceph, GlusterFS, Lustre, BeeGFS, OCFS2,
   GFS2, VMFS) в homelab на 1–2 узлах дают меньше, чем стоят.
7. Для обмена «как есть» внутри LAN достаточно SMB/NFS; для интернета —
   HTTP-семейство и синхронизация, а не туннелирование SMB.
8. Официальных цифр по RAM/CPU у файловых протоколов практически нет — выбор
   делается по архитектуре (ядро vs userspace, RPC vs FUSE), а не по таблицам
   производителей.

## Что не подтверждено

Сводно (детали — в разделах «Не подтверждено» каждой главы):

- Официальных цифр RAM/CPU/пропускной способности нет: SMB (Samba и Microsoft),
  NFS (кроме замеров LOCALIO), 9P, virtiofs, WebDAV/davfs2, SFTP/FTP, rsync,
  NBD, iSCSI, iSER, NVMe-oF, FC, FCoE, AoE, SRP, SMB Direct, Lustre, GlusterFS,
  MooseFS, HDFS, XtreemFS, JuiceFS, RustFS, Garage, SeaweedFS, Zenko, lakeFS,
  s3fs/goofys/Mountpoint, Nextcloud, Seafile, Syncthing, Resilio, rsync, Unison.
- «Samba не поддерживает SMB Direct и SMB over QUIC» — аргумент от отсутствия
  параметров в `smb.conf(5)`, а не цитата (wiki.samba.org из сети сессии
  недоступен).
- Точная версия ядра с `ksmbd` в kernel-doc не указана; версия LOCALIO (6.12+)
  и virtiofs (5.4) проверена по `Kconfig` тегов, а не по merge-коммитам.
- AFP: точная история deprecation у Apple — по Netatalk NEWS и архивному
  Programming Guide; release notes Apple машинно-читаемо не извлеклись.
- Garage: где лежат метаданные и какая модель консистентности — официальной
  страницы получить не удалось.
- Ceph RGW: устройство индексов бакета/метаданных в RADOS по первоисточнику не
  проверялось.
- rsync: официальный tech report (`rsync.samba.org/tech_report/`) не открылся,
  алгоритм описан без прочитанного первоисточника.
- Swift: общей страницы про consistency нет (404), подтверждена только eventual
  consistency в контексте DLO.
- Постраничные первоисточники по share-ссылкам/группам/ролям в «облачных
  дисках» и по зашифрованным библиотекам Seafile не собирались.
