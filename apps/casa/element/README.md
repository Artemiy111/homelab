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

Секреты приходят из Vault пятью путями (`db`, `registration`,
`@fcm/fcm-server-key`, `@livekit/livekit-credentials`,
`@turn/turn-credentials`).

Креды TURN и LiveKit дублируются в конфигах на узле
(`/storage/apps/element/turn/turnserver.conf`, `livekit/config.yaml`): их читает
coturn и livekit, а не Kubernetes. При ротации в Vault эти файлы надо править
руками.
Конфигурации генерируются в персистентном каталоге данных сервиса, там же
сохраняется timezone `Asia/Yekaterinburg`.

База Synapse (`synapse`) живёт в общем кластере CNPG `shared`
(`shared-rw.databases.svc.cluster.local`): роль `synapse` и база объявлены в
`platform/casa/cnpg/`. Пароль лежит в пути `kv/element/db` и подаётся в два
Secret'а: `element/element-db-auth` (читает synapse) и
`databases/element-db-auth` (читает CNPG). Строка подключения задана в
`homeserver.yaml` в конфиге сервиса.

Push-уведомления Sygnal не настроены: для них необходимы реальные FCM
credentials.

Первый администратор и проверка — в `RUNBOOK.md`.
