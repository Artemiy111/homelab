# Element / Matrix

Element — web-клиент Matrix, а Synapse — его homeserver. В этом проекте также
настроен Element Call: MatrixRTC с LiveKit SFU для групповых аудио- и
видеозвонков. Стек рассчитан на доступ из LAN и tailnet; публичный NAT-path не
используется.

## Состав

- `element-web` — веб-интерфейс по `https://element.example.com/`;
- `synapse` — Matrix API по пути `/_matrix` того же домена;
- `livekit` — SFU для Element Call;
- `matrix-rtc-auth` — выдаёт LiveKit-токены по `/livekit/jwt`;
- `turn` — coturn для клиентов, которым нужен relay;
- Redis — внутреннее хранилище Synapse и LiveKit;
- база `synapse` живёт в CloudNativePG в общем кластере `shared`
  (namespace `databases`), см. `platform/casa/cnpg/README.md`.

Traefik маршрутизирует HTTP(S): корень домена ведёт в Element Web,
`/_matrix` — в Synapse, `/livekit/sfu` — в LiveKit, `/livekit/jwt` — в
MatrixRTC authorization service.

Для домена Matrix ID (`example.com`) Synapse также публикует
`/.well-known/matrix/client`. В нём объявлен LiveKit MatrixRTC focus — именно
так Element обнаруживает сервер звонков.

Там же публикуется Matrix Federation delegation на HTTPS-порт `443`; он нужен
MatrixRTC authorization service, чтобы проверить OpenID-токен пользователя у
Synapse. Delegation ссылается на apex-домен (`example.com`), поэтому apex обязан
резолвиться (A-запись в Technitium) и иметь маршрут `/_matrix` на слушателе
`apex` Gateway.

Порядок правил в HTTPRoute значим: Traefik выбирает маршрут по длине правила, а
Gateway API — по порядку правил в списке. Поэтому точные совпадения (`/livekit/*`)
объявлены выше префиксов, а сам клиент Element ловит всё оставшееся последним
правилом без `matches`.

## Сеть

Talk и Element работают одновременно и не конкурируют за порты.

| Назначение | Порты |
| --- | --- |
| Element TURN | `3479/tcp,udp` |
| Element TURN relay | `21000–21499/tcp,udp` |
| LiveKit signaling/API | `7880/tcp` через Traefik, `7881/tcp` для WebRTC fallback |
| LiveKit media | `50000–50499/udp` |
| Nextcloud Talk (отдельный сервис) | `3478/tcp,udp`, `20000–20499/tcp,udp` |

LiveKit рекламирует LAN-адрес сервера (`<node1-ip>`), а не автоматически
найденный публичный IP. Это необходимо для стабильных звонков из LAN/Tailscale.
Адрес берётся из `status.hostIP`, поэтому переезд узла переживает сам.

TURN-серверы, которые Synapse отдаёт клиентам, объявлены в `homeserver.yaml`
литералом: конфиг Synapse — статический файл, значения из `status.hostIP` в
него не подставляются. Это единственное место юнита, где адрес узла
задублирован; при переезде узла его правят вместе с `externalIPs` Traefik.

## Порядок применения

Внутри приложения порядок задают волны Argo: namespace, затем конфиги, секреты
Vault, том и сетевые политики, затем Redis и только после него прикладные
Deployment. Порядок нужен при холодном стенде, когда Secret'а от оператора ещё
нет: под, стартовавший раньше секрета, висит в `CreateContainerConfigError`.
База Synapse живёт в другом приложении (`platform/casa/cnpg`) с более ранней
волной, поэтому порядок «сначала база» задаётся там, а не здесь.

Init-контейнеров ожидания (`wait-for-db`, `wait-for-redis`) в юните нет.
Готовность зависимости они проверяли только на старте пода, а при недоступной
базе в момент рестарта всё равно не спасали: держали под в `Init`, пока сервис
не отвечает. Цена отказа — если Postgres или Redis лежит в момент рестарта,
Synapse падает на старте и kubelet возвращается к нему по экспоненциальной
задержке `CrashLoopBackOff`: восстановление после возврата базы занимает до
пяти минут вместо нескольких секунд.

## Изоляция

Все поды работают не от root, с read-only корневой ФС, сброшенными
capabilities и `RuntimeDefault` seccomp; токен ServiceAccount в них не
монтируется. Записывать приложениям разрешено только тома: `/data` у Synapse,
`/tmp` у всех, каталог конфигов nginx у Element Web. Конфиги и ключи из
Secret'ов монтируются только на чтение.

Сеть закрыта в обе стороны. Внутрь пускают Traefik (порты сервисов) и vmagent
(метрики); наружу — DNS, адреса кластера и LAN, а из внешнего мира только порты
протокола: federation у Synapse, OIDC и LiveKit у сервиса авторизации. Доступ к
публичному адресу стека разрешён отдельно: `matrix-rtc-auth` ходит в Synapse и
LiveKit по публичным именам, а не по service-DNS, и трафик выходит из пода и
возвращается через Traefik. `livekit` и `coturn` живут в `hostNetwork`, где
NetworkPolicy не применяется — медиа идёт напрямую через узел.

## Учётные записи

Публичная регистрация выключена. Учётка появляется либо при первом входе через
OIDC-провайдера (localpart собирается из email), либо через shared-secret
регистрацию. Прав администратора сервера такая учётка не получает.

Администратор не объявляется конфигом: Synapse не даёт такого способа — флаг
`admin` ставится при создании учётки либо через Admin API уже существующим
администратором. Поэтому администратор — это учётка, созданная бутстрапом до
первого входа через провайдера: дальше вход идёт через него же и подхватывает
готовую учётку. Job в манифестах для этого не заводится: он умеет только
создавать учётку, но не повышать уже созданную, и ему нужен пароль
администратора.

Цена решения: администратор живёт в базе `synapse`, а не в git. Пересоздание
базы уносит его вместе с содержимым, и бутстрап приходится повторять.

## Обслуживание

Секреты приходят из Vault тремя путями: `element/db`, `element/secrets`,
`element/oidc`. Приложения читают их файлами, а не переменными окружения:
Synapse — через `*_path` (`registration_shared_secret_path`,
`turn_shared_secret_path`, `client_secret_path`), `matrix-rtc-auth` — через
`LIVEKIT_*_FROM_FILE`, LiveKit — через `key_file`.

Два исключения, где файла не получилось:

- **coturn** не умеет `*_FILE` вовсе, поэтому его `turnserver.conf` целиком
  рендерит оператор секретов из Vault. В git лежит шаблон, а не файл.
- **Пароль Postgres у Synapse** остаётся переменной `PGPASSWORD`: у Synapse нет
  `password_path`, а libpq-овский `passfile` принимает только файл с правами
  `0600`. На secret-томе владелец файла — root, а не-root процесс получает
  доступ через fsGroup, то есть с групповым чтением; файл с правами `0440`
  libpq молча игнорирует и соединение падает с «no password supplied».

Ротацию в Vault поды переживают перекатом: оператор патчит шаблон Deployment, а
файлы читаются на старте процесса. Перечитывания на лету не умеет ни одно из
приложений.

`client_id` OIDC-клиента — не секрет и объявлен прямо в `homeserver.yaml`; из
Vault читается только `client_secret`. Копия `client_id` в `kv/element/oidc`
осталась от прежней схемы и манифестом не используется.

База Synapse (`synapse`) живёт в общем кластере CNPG `shared`
(`shared-rw.databases.svc.cluster.local`): роль `synapse` и база объявлены в
`platform/casa/cnpg/`. Пароль лежит в пути `kv/element/db` и подаётся в два
Secret'а: `element/element-db-auth` (читает synapse) и
`databases/element-db-auth` (читает CNPG). Строка подключения задана в
`homeserver.yaml` в конфиге сервиса.

Push-уведомления Sygnal не настроены: для них необходимы реальные FCM
credentials.

Первый администратор и проверка — в `RUNBOOK.md`.
