# Nextcloud Talk: серверная медиа-топология и высокая загрузка macOS

> Дата проверки: 2026-08-18  
> Метод: официальные документация и исходники Nextcloud Talk/AIO/HPB, плюс безопасная проверка локальной конфигурации и доступных с сервера сокетов. Секреты не читались.

## Краткий вывод

Чтобы звонок шёл через собственный сервер, нужен **High Performance Backend (HPB) с SFU**. В этом репозитории он уже предусмотрен: `talk-hpb` использует официальный контейнер `ghcr.io/nextcloud-releases/aio-talk`, в котором есть signaling, Janus media gateway/SFU, NATS и eturnal TURN/STUN. Это не P2P-mesh.

Важно различать компоненты:

| Компонент | Что делает | Переносит обычное медиа звонка? |
|---|---|---|
| Signaling | аутентификация, согласование WebRTC-сессии | Нет |
| SFU (Janus/HPB) | получает один поток от клиента и пересылает его подписчикам | Да |
| STUN | помогает найти доступные сетевые адреса | Нет |
| TURN | relay, когда клиент не может достучаться до нужного WebRTC-адреса | Только fallback/ограниченные сети |

Без HPB Talk сначала строит прямую P2P-сетку; TURN тогда является лишь последней попыткой соединения. С HPB клиент публикует один поток в SFU, а сервер распределяет его участникам. Следовательно, **одного TURN недостаточно**, чтобы перевести обычные звонки с P2P на сервер. [Официальное описание масштабирования](https://nextcloud-talk.readthedocs.io/en/stable/scalability/), [документация TURN](https://github.com/nextcloud/spreed/blob/main/docs/TURN.md).

## Что есть в репозитории и что проверено

- `talk-hpb/compose.yaml` публикует signaling через Traefik и TURN/STUN на `3478/tcp,udp`; диапазон relay `20000–20499/tcp,udp` также опубликован.
- В образе запущены серверный SFU и локальный TURN; это соответствует официальному способу развернуть standalone HPB с `aio-talk`. [Quick install](https://nextcloud-talk.readthedocs.io/en/stable/quick-install/).
- `https://talk-signaling.example.com/standalone-signaling/api/v1/welcome` ответил `Welcome`, версия `2.1.1~docker`: HTTP/TLS-прокси до signaling работает. Это **не** проверка регистрации HPB в Talk и не проверка UDP-медиа.
- На сервере слушаются `<node1-ip>:3478` (TCP/UDP) и начало relay-диапазона `:20000` (TCP/UDP). У пользователя агента нет прав читать Docker API и настройки firewalld, поэтому состояние регистрации Talk, фактический `.env`, логи контейнера и разрешение firewall не подтверждены.

### Существенное наблюдение о битрейте

Версионируемый `talk-hpb/init.sh` создаёт новые `.env` со следующими значениями:

```text
TALK_MAX_STREAM_BITRATE=12582912   # 12 Miбит/с
TALK_MAX_SCREEN_BITRATE=20971520   # 20 Miбит/с
```

Официальный `aio-talk` при отсутствии этих переменных выбирает соответственно `1048576` и `2097152` (1 и 2 Miбит/с). Значит, если серверный `.env` был создан текущим скриптом и не менялся, разрешённый потолок камеры увеличен в 12 раз, а шаринга — в 10 раз по сравнению с дефолтом образа. Это не доказывает причину 80% CPU, но это **наиболее сильная гипотеза в текущей конфигурации**: кодирование/декодирование 1080p/30 fps и большего битрейта легко грузят ноутбук, особенно при виртуальном фоне или screen share. [Исходник AIO `start.sh`](https://github.com/nextcloud/all-in-one/blob/main/Containers/talk/start.sh).

## Нормальны ли 80% CPU на Mac?

По одной цифре — нельзя сказать. Нагрузка браузера от получения и декодирования нескольких видеопотоков ожидаема даже при SFU: SFU устраняет дублирование **исходящего** потока и P2P-mesh, но не делает декодирование принимаемого видео бесплатным. Официальная документация отдельно говорит, что декодирование всех потоков сильно нагружает устройство; отключение видео оставляет около 50 kbit/s аудио и устраняет большую часть работы по декодированию. [Scalability](https://nextcloud-talk.readthedocs.io/en/stable/scalability/).

В Talk качество при менее чем 20 видеопотоках может быть `High`, с идеалом 1440×1080 при 30 fps. Дополнительные функции браузерного клиента используют WASM/TensorFlow Lite, в том числе background blur. Поэтому 80% CPU для одной видеоконференции с тяжёлым фоном/1080p может быть ожидаемым, но для простого 1:1 без blur и screen share — повод сравнить браузер, аппаратное кодирование и фактический media path. [Call experience](https://nextcloud-talk.readthedocs.io/en/stable/call-experience/), [System requirements](https://nextcloud-talk.readthedocs.io/en/stable/system-requirements/).

## Правильная сетевая модель

```text
Nextcloud Talk client ── HTTPS/WSS ──► Traefik ──► signaling (8081)
       │
       └── WebRTC media (UDP preferred) ──► Janus SFU / HPB
                         └─ если путь заблокирован ─► TURN ─► HPB relay ports
```

Для участников вне LAN нужны не только Docker-публикации, но и правила firewall и проброс на маршрутизаторе:

- `3478/udp` и `3478/tcp` для текущего TURN/STUN;
- `20000–20499/udp` и, при необходимости TCP, для relay-диапазона, настроенного этим репозиторием;
- публичный DNS/маршрут до тех же адресов.

Официальная документация HPB указывает по умолчанию media-диапазон `20000–40000`; данный проект осознанно сузил его до 500 портов. Его необходимо открыть целиком, а не только `3478`. Для максимально ограниченных клиентских сетей Nextcloud рекомендует TURN также на `443` (и `turn:` + `turns:`, UDP + TCP), но HPB и TURN не могут занимать один IP:443 — для этого потребуется отдельный IP либо отдельная машина. [TURN with HPB](https://github.com/nextcloud/spreed/blob/main/docs/TURN.md#turn-server-and-nextcloud-talk-high-performance-backend).

Текущий README упоминает в разделе firewall лишь `3478`; это неполно для внешних вызовов через relay, поскольку relay-диапазон тоже должен быть достижим. Это вывод из сопоставления compose-конфигурации с официальной сетевой моделью; настройки сейчас не изменялись.

## Что проверить до изменения конфигурации

Все команды ниже диагностические. На сервере их следует выполнять от `artlab` по принятой в репозитории модели доступа; они не печатают секреты.

1. В **Администрирование → Talk** убедиться, что HPB URL — `https://talk-signaling.example.com/standalone-signaling`, секрет совпадает, а проверка соединения зелёная. Либо проверить список серверов:

   ```sh
   docker exec -u www-data nextcloud-app php occ talk:signaling:list
   docker exec -u www-data nextcloud-app php occ talk:stun:list
   docker exec -u www-data nextcloud-app php occ talk:turn:list
   ```

2. Вызвать `docker logs --since=15m talk-hpb` сразу после тестового звонка: искать ошибки ICE/TURN/Janus, а не только HTTP healthcheck.

3. Проверить firewalld и маршрутизатор для **всего** `20000–20499`, особенно UDP. Проверка должна выполняться с устройства вне LAN: локальный звонок не доказывает доступность NAT path.

4. В DevTools браузера собрать `chrome://webrtc-internals` во время двух тестов: (а) обычный звонок, (б) временно принудительный `iceTransportPolicy = 'relay'` по [официальной инструкции теста TURN](https://github.com/nextcloud/spreed/blob/main/docs/TURN.md#testing-the-turn-server). Сравнить выбранный ICE candidate (`host`/`srflx`/`relay`), packet loss, RTT, jitter и retransmissions.

5. Провести матрицу CPU на Mac с одним и тем же собеседником: audio-only → камера без blur → камера с blur → screen share; затем 1:1 и 3+ участников. Тестировать Chrome и Firefox с питанием от сети. Это отделит стоимость эффекта/кодека от проблемы маршрутизации. Nextcloud также рекомендует Chrome или Firefox для desktop, отмечая более слабую WebRTC-реализацию у прочих браузеров. [Scalability](https://nextcloud-talk.readthedocs.io/en/stable/scalability/).

6. Сверить фактические значения `TALK_MAX_*` на сервере с пунктом выше. Для снижения нагрузки сначала разумно опустить их к официальным дефолтам, затем повторить одинаковый тест. Это изменение требует отдельного решения и развертывания, поэтому в рамках исследования оно не применялось.

## Рекомендуемое решение

1. Не заменять HPB на один TURN: оставить и зарегистрировать HPB/SFU как основную серверную топологию.
2. Сначала доказать регистрацию HPB и успешный WebRTC путь по метрикам/ICE, затем обеспечить внешний доступ к relay-диапазону.
3. Если `TALK_MAX_*` действительно равны 12/20 Miбит/с, начать с отката к 1/2 Miбит/с и измерить качество/CPU. Поднимать пределы следует только при подтверждённой необходимости.
4. Для сетей, где разрешён лишь 443, запланировать отдельный public IP/хост для `turns:443`; это улучшение совместимости, но не обязательное условие для работы внутри LAN.

## Первичные источники

- [Nextcloud Talk — Quick install / HPB](https://nextcloud-talk.readthedocs.io/en/stable/quick-install/)
- [Nextcloud Talk — Scalability](https://nextcloud-talk.readthedocs.io/en/stable/scalability/)
- [Nextcloud Talk — TURN configuration](https://github.com/nextcloud/spreed/blob/main/docs/TURN.md)
- [Nextcloud Talk — Call experience](https://nextcloud-talk.readthedocs.io/en/stable/call-experience/)
- [Nextcloud Talk — System requirements](https://nextcloud-talk.readthedocs.io/en/stable/system-requirements/)
- [Nextcloud AIO — Talk container start script](https://github.com/nextcloud/all-in-one/blob/main/Containers/talk/start.sh)
- [HPB signaling / Janus setup](https://github.com/strukturag/nextcloud-spreed-signaling#setup-of-janus)
