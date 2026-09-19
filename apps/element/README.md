# Element / Matrix

Element — web-клиент Matrix, а Synapse — его homeserver. В этом проекте также
настроен Element Call: MatrixRTC с LiveKit SFU для групповых аудио- и
видеозвонков. Стек рассчитан на доступ из LAN и tailnet; публичный NAT-path не
используется.

Разворачивается манифестами в apps/element/k8s/.

## Состав

- `element-web` — веб-интерфейс по `https://element.example.com/`;
- `synapse` — Matrix API по пути `/_matrix` того же домена;
- `livekit` — SFU для Element Call;
- `matrix-rtc-auth` — выдаёт LiveKit-токены по `/livekit/jwt`;
- `turn` — coturn для клиентов, которым нужен relay;
- PostgreSQL и Redis — внутренние хранилища Synapse и LiveKit.

Traefik маршрутизирует HTTP(S): корень домена ведёт в Element Web,
`/_matrix` — в Synapse, `/livekit/sfu` — в LiveKit, `/livekit/jwt` — в
MatrixRTC authorization service.

Для домена Matrix ID (`example.com`) Synapse также публикует
`/.well-known/matrix/client`. В нём объявлен LiveKit MatrixRTC focus — именно
так Element обнаруживает сервер звонков.

Там же публикуется Matrix Federation delegation на HTTPS-порт `443`; он нужен
MatrixRTC authorization service, чтобы проверить OpenID-токен пользователя у
Synapse.

## Сеть

Talk и Element работают одновременно и не конкурируют за порты.

| Назначение | Порты |
| --- | --- |
| Element TURN | `3479/tcp,udp` |
| Element TURN relay | `21000–21499/tcp,udp` |
| LiveKit signaling/API | `7880/tcp` через Traefik, `7881/tcp` для WebRTC fallback |
| LiveKit media | `50000–50499/udp` |
| Nextcloud Talk (отдельный сервис) | `3478/tcp,udp`, `20000–20499/tcp,udp` |

LiveKit рекламирует LAN-адрес сервера (`192.0.2.10`), а не автоматически
найденный публичный IP. Это необходимо для стабильных звонков из LAN/Tailscale.

## Первый администратор

Публичная регистрация отключена. Первого администратора создают вручную;
пользователь входит в Element под своим логином и паролем, а его Matrix ID
получает вид `@YOUR_LOGIN:example.com`.

## Обычные пользователи

Администратор сервера создаёт обычные учётные записи без включения публичной
регистрации. Созданная учётная запись не получает прав администратора.

## Обслуживание

Секреты сервиса хранятся в зашифрованном `apps/element/secrets.enc.env`.
Конфигурации генерируются в персистентном каталоге данных сервиса, там же
сохраняется timezone `Asia/Yekaterinburg`.

PostgreSQL хранит данные в персистентном каталоге сервиса и использует штатный
каталог образа `/var/lib/postgresql/data`. Не удаляйте эти данные при
обновлении.

Push-уведомления Sygnal не настроены: для них необходимы реальные FCM
credentials.

## Проверка

```sh
curl -fsS https://element.example.com/_matrix/client/versions
curl -fsS https://element.example.com/livekit/jwt/healthz
```

Полная проверка Element Call требует двух авторизованных клиентов в LAN или
tailnet: создать комнату, начать звонок и проверить аудио/видео.
