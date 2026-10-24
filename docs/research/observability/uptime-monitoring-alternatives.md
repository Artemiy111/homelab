# Декларативная альтернатива Uptime Kuma

Дата проверки: 2026-08-14.

## Вывод

Для этого homelab оптимальная замена Uptime Kuma — **self-hosted Gatus**. Его
штатная конфигурация — YAML-файл (или каталог YAML-файлов), который можно
хранить в Git и монтировать в контейнер. Те же файлы описывают проверки,
условия успешности, пороги алертов, уведомления, хранилище и внешний вид
встроенного dashboard/status page. Поэтому собственный reconciler и обращение
к внутреннему API не нужны.

Gatus покрывает текущие 15 мониторов без функциональных потерь:

- HTTP/HTTPS, проверку кода и тела ответа;
- проверку срока действия и валидности TLS-сертификата;
- разрешение имени через явно заданный DNS resolver для HTTP-клиента;
- отдельные DNS-запросы к указанному DNS-серверу;
- TCP-подключения;
- уведомления с порогом последовательных ошибок и сообщением о восстановлении;
- встроенный web dashboard/status page и сохранение истории в SQLite;
- Docker deployment и автоматическую перечитку конфигурации.

Официальный README описывает [file-based configuration, объединение нескольких
YAML-файлов и подстановку переменных окружения](https://github.com/TwiN/gatus#configuration),
[типы проверок и условия](https://github.com/TwiN/gatus#endpoints),
[алерты](https://github.com/TwiN/gatus#alerting),
[SQLite/PostgreSQL storage](https://github.com/TwiN/gatus#storage),
[Docker deployment](https://github.com/TwiN/gatus#docker) и
[перезагрузку конфигурации на лету](https://github.com/TwiN/gatus#reloading-configuration-on-the-fly).
Проект активно поддерживается: официальный список релизов содержит
[v5.36.0 от 19 мая 2026 года](https://github.com/TwiN/gatus/releases/tag/v5.36.0).

## Сравнение

| Вариант | Декларативность | Нужные проверки | UI/status page | Сложность для homelab | Решение |
|---|---|---|---|---|---|
| Gatus | Нативный YAML, каталог файлов, env-подстановки | HTTP(S), TLS, DNS, TCP и другие | Встроен | Один контейнер и SQLite | **Выбрать** |
| Prometheus + blackbox_exporter + Alertmanager + Grafana | Нативные YAML/JSON-файлы во всех компонентах | Наиболее полное покрытие | Grafana — dashboard, но не простая status page из коробки | 3–4 сервиса, scrape/relabel rules, alert rules, routing и dashboard provisioning | Выбрать позже, если нужен общий metrics/observability stack |
| Beszel | Compose декларативен, но системы и алерты в основном хранятся в PocketBase | Метрики хоста/контейнеров, а не полноценные HTTP/DNS/TCP probes | Встроен | Hub + agent | Дополнение, не замена |
| Healthchecks | Настройки сервера декларативны, checks ориентированы на UI/API | Push/heartbeat периодических задач | Встроен | Web + БД | Дополнение для backup/cron jobs, не замена |
| Monika | YAML/JSON-конфигурация | HTTP/TCP/DNS и уведомления | Нет сопоставимой встроенной status page | Один процесс, но dashboard придётся добавлять | Слабее Gatus для этой задачи |

### Gatus

Gatus специально совмещает probing, alerting и status dashboard. Для HTTP
можно проверить `[STATUS]`, JSON/body, response time и
`[CERTIFICATE_EXPIRATION]`; `client.insecure` по умолчанию равен `false`, то
есть цепочка и имя сертификата проверяются. `client.dns-resolver` позволяет
направить разрешение реального HTTPS URL через `tcp://<node1-ip>:53`.
Отдельный DNS endpoint отправляет запрос непосредственно серверу из `url` и
позволяет проверить `DNS_RCODE` и ответ. TCP endpoint задаётся URL вида
`tcp://host:port`. Все эти возможности и примеры находятся в
[официальной конфигурации Gatus](https://github.com/TwiN/gatus/blob/master/README.md).

Для сохранения uptime и событий достаточно SQLite-файла на persistent volume.
Конфигурацию следует монтировать **каталогом**, а не одиночным bind-mounted
файлом: официальная документация предупреждает, что обновление одиночного
bind mount может не обнаружиться. Безопасный режим для GitOps — валидировать
новый образ и YAML до deploy, затем пересоздавать контейнер; hot reload можно
считать удобством, а не единственным способом применения.

Ограничение Gatus: это не замена системе метрик хоста, логам и Grafana. Также
экземпляр на том же сервере не обнаружит собственное полное отключение так,
чтобы доставить уведомление наружу. Для такого отказа всё равно нужен внешний
dead-man check или второй probe на другом устройстве.

### Prometheus + blackbox_exporter + Alertmanager + Grafana

Это наиболее зрелый и расширяемый вариант. Официальный blackbox_exporter
поддерживает [HTTP/HTTPS, DNS, TCP, ICMP, gRPC и file-based modules](https://github.com/prometheus/blackbox_exporter),
включая TLS-настройки и проверку конкретного DNS target в
[схеме конфигурации](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md).
Prometheus хранит временные ряды и вычисляет alert rules; Alertmanager нативно
задаёт в файле [маршрутизацию и receivers](https://prometheus.io/docs/alerting/latest/configuration/)
и имеет [email, Discord и generic webhook integrations](https://prometheus.io/docs/alerting/latest/integrations/).
Grafana умеет provision-ить из Git
[data sources и dashboards файлами](https://grafana.com/docs/grafana/latest/administration/provisioning/).

Но ради 15 binary uptime-проверок придётся сопровождать несколько контейнеров,
два уровня target/module configuration, PromQL rules, Alertmanager routing и
Grafana dashboard. Grafana — операторский dashboard, не столь простая публичная
status page. Стек оправдан, если репозиторий одновременно переходит к метрикам
CPU/RAM/disk/container/application; только как замена Kuma он избыточен.

### Beszel и Healthchecks

[Beszel](https://github.com/henrygd/beszel) предназначен прежде всего для
метрик серверов и контейнеров: CPU, память, диски, сеть, температуры и статусы
контейнеров. Его hub/agent архитектура и UI полезны рядом с Gatus, но не дают
равноценного декларативного набора HTTP/TLS/DNS/TCP probes. Проект активен
([v0.18.7 от 5 апреля 2026 года](https://github.com/henrygd/beszel/releases/tag/v0.18.7)),
однако решает другую задачу.

[Healthchecks](https://healthchecks.io/docs/) — dead-man switch для cron jobs и
периодических процессов: задача сама отправляет ping, а отсутствие ping вызывает
аварию. Есть [официальный Docker deployment](https://healthchecks.io/docs/self_hosted_docker/),
но это не pull-prober пользовательских URL, DNS и TCP-портов. Его стоит добавить
позже для backup jobs, а не ставить вместо Gatus.

## Отображение текущих 15 мониторов

| Текущая группа | Количество | Представление в Gatus |
|---|---:|---|
| Pi-hole, Jitsi, Nextcloud, Gitea, Immich, Dawarich, Jellyfin, Navidrome, Uptime Kuma | 9 | HTTPS URL; ожидаемый 2xx; custom Pi-hole resolver; валидный TLS; разумный порог до окончания сертификата |
| Traefik | 1 | HTTPS URL; условие `[STATUS] == 401`; custom Pi-hole resolver; TLS expiration |
| Sure | 1 | `http://<node1-ip>:40060/`; ожидаемый 2xx |
| 3x-ui | 1 | `tcp://3x-ui:2053`; `[CONNECTED] == true` |
| Pi-hole DNS | 1 | URL `<node1-ip>`; A-query для `uptime.example.com`; `DNS_RCODE == NOERROR`; желательно также проверить ожидаемый LAN IP |
| Gitea SSH | 1 | `tcp://<node1-ip>:2222`; `[CONNECTED] == true` |
| Xray inbound | 1 | `tcp://<node1-ip>:8443`; `[CONNECTED] == true`; оставить падающим, пока порт действительно не слушает |

Во всех HTTPS endpoints следует явно указать resolver Pi-hole. Это сохраняет
исходную цель: одна проверка охватывает локальный DNS, TLS, Traefik и само
приложение. Отдельный DNS endpoint локализует отказ Pi-hole. Для HTTPS стоит
добавить условие, например `[CERTIFICATE_EXPIRATION] > 168h`, которого сейчас
нет в JSON Kuma. Порог алерта `failure-threshold: 3` близок к текущему поведению
`maxretries: 2`; `send-on-resolved: true` сообщает о восстановлении.

Сам Gatus после миграции нужно проверять по его внешнему HTTPS URL. Это
обнаруживает проблемы маршрута, пока процесс Gatus жив, но не устраняет
необходимость внешней проверки всего сервера.

## План миграции

1. Добавить каталог `gatus/` с закреплённой версией образа, `compose.yaml`,
   `config/` и persistent SQLite volume. Не использовать плавающий тег
   `latest`/`stable`.
2. Разнести YAML как минимум на общие настройки/уведомления и endpoints.
   Секреты уведомлений подставлять из `.env`, не хранить в Git.
3. Перенести все 15 monitors по таблице выше. Сохранить интервал `60s`, timeout,
   три последовательные неудачи до алерта и уведомление о восстановлении.
4. Перед применением проверить YAML тестовым запуском той же закреплённой версии.
   Временно запустить Gatus параллельно Kuma и сравнить результаты минимум
   24–48 часов; ожидаемая авария Xray не должна считаться расхождением.
5. Проверить не только зелёный dashboard, но и доставку уведомления: временно
   направить один тестовый endpoint на закрытый порт, дождаться алерта, вернуть
   target и дождаться resolved notification.
6. Переключить Traefik hostname `uptime...` на Gatus либо сначала дать Gatus
   отдельное имя и выполнить переключение после наблюдения. Историю Kuma не
   переносить: для небольшого homelab ценность ниже риска и сложности мигратора.
7. Остановить Kuma, но сохранить `/app/data` на один backup cycle. После этого
   удалить sync container/script и Kuma configuration отдельным коммитом.
8. Настроить внешний hosted check либо второй Gatus/Healthchecks probe вне
   сервера для обнаружения питания, сети и полного падения самого Gatus.

## Рекомендованное решение

Перейти с Uptime Kuma на один контейнер Gatus + SQLite, хранить всю конфигурацию
проверок в YAML в этом репозитории и применять обычным commit/push/deploy.
Prometheus stack пока не вводить. Beszel рассматривать отдельно, если появится
задача собирать системные метрики, а Healthchecks — когда потребуется контролировать
запуски резервного копирования и cron/systemd timers.
