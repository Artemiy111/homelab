# Камера домофона (Novihome COMFY 10 FHD WIFI KIT DARK v.4102) и Home Assistant

Дата проверки: 2026-08-21 (обновлено после сетевой диагностики).

## Вывод

Комплект опознан: **Novihome COMFY 10 FHD WIFI KIT DARK v.4102** (монитор 10.1"
+ вызывная панель) российского бренда [NOVIHOME](https://novihome.ru/) (Novicam).
По официальной карточке товара комплект работает с приложениями **Smart Life и
Tuya Smart** — это платформа **Tuya**
([страница продукта](https://novihome.ru/catalog/domofoniya/komplekty/komplekt-videodomofona-novihome-comfy-10-fhd-wifi-kit-dark-ver-4102/)).
Сетевая диагностика это подтверждает: единственный открытый порт — TCP **6668**,
стандартный локальный порт камер Tuya; RTSP (554), HTTP-интерфейс и ONVIF
отсутствуют.

Подключение к Home Assistant возможно через **go2rtc + аккаунт Tuya Smart**:
go2rtc начиная с v1.9.13 умеет забирать WebRTC-поток камер Tuya (с двусторонним
звуком) ([tuya README](https://raw.githubusercontent.com/AlexxIT/go2rtc/master/internal/tuya/README.md)).
Нюансы:

- Локального RTSP у комплекта нет — видео идёт через инфраструктуру Tuya
  (сигналинг через облако, сам медиапоток обычно P2P).
- Для go2brtc нужен именно **Tuya Smart**: «Smart Life accounts are NOT
  supported» — если домофон уже привязан к Smart Life, его нужно отвязать и
  добавить заново в Tuya Smart ([tuya README](https://raw.githubusercontent.com/AlexxIT/go2rtc/master/internal/tuya/README.md)).
- Альтернатива — Tuya Cloud API через [iot.tuya.com](https://iot.tuya.com)
  (нужны `device_id`, `client_id`, `client_secret`, `uid` и подписка на сервис
  «IoT Video Live Stream»).

LocalTuya видео не даст (нет RTSP-потока как такового); он может пригодиться
только для не-видео сущностей.

## Идентификация устройства (проверено 2026-08-21)

| Факт | Значение | Источник |
|---|---|---|
| Модель | COMFY 10 FHD WIFI KIT DARK v.4102 | коробка, QR → `novihome.ru/quick-contacts`; [карточка товара](https://novihome.ru/catalog/domofoniya/komplekty/komplekt-videodomofona-novihome-comfy-10-fhd-wifi-kit-dark-ver-4102/) |
| Приложения | Smart Life, Tuya Smart | карточка товара |
| Прошивка монитора | NOVIGUI V5.1.1.35, релиз 2024-07-12, Cloud ID `bkdze35f61513090b34d` | фото сервисного меню монитора |
| Открытые порты (<device-ip>) | только TCP 6668 | nmap/nc сканирование |
| RTSP/ONVIF/HTTP | отсутствуют (554/80/443/8000/8899/34567 закрыты) | сканирование |
| MAC | рандомизированный (`2a:56:0f:…`, locally administered) | arp |

Проба go2rtc v1.9.14 c `tuya://<device-ip>:6668` закономерно вернула
«wrong query params»: источник требует параметры облачного API, а не LAN-адрес.

## Путь подключения

1. Установить приложение **Tuya Smart** (не Smart Life), зарегистрироваться,
   регион для РФ — Western Europe; привязать домофон (если он уже в Smart Life —
   отвязать и привязать заново в Tuya Smart).
2. Поставить в HA [go2rtc](https://github.com/AlexxIT/go2rtc) (add-on или custom
   component [WebRTC Camera](https://github.com/AlexxIT/WebRTC)); в веб-интерфейсе
   go2rtc: Add → Tuya → регион/email/пароль → выбрать домофон. go2rtc сам
   сформирует источник вида
   `tuya://protect-eu.ismartlife.me?device_id=…&email=…&password=…`
   ([tuya README](https://raw.githubusercontent.com/AlexxIT/go2rtc/master/internal/tuya/README.md)).
3. Показывать поток в HA (карточка/WebRTC), при желании — запись в Frigate
   ([гайд configuring go2rtc](https://docs.frigate.video/guides/configuring_go2rtc/)).
4. Вызов на смартфон работает штатно через приложение Tuya; событие нажатия
   кнопки панели в HA — проверить после привязки (сущности официальной
   интеграции Tuya либо автоматизация по push).

Ограничения: без интернета Tuya живой поток не поднять (локального протокола в
go2rtc нет); зависимость от доступности облака Tuya и аккаунта.

## Как проверить RTSP/ONVIF (уже выполнено)

Выполнено 2026-08-21 против `<device-ip>`: `nc`-обход типовых портов камер +
nmap — только 6668/TCP. Типовые пути RTSP из документации
[Generic Camera](https://www.home-assistant.io/integrations/generic/) и
[go2rtc](https://github.com/AlexxIT/go2rtc) здесь неприменимы. Если в будущем
появится прошивка с RTSP — вернуться к схеме Generic Camera/ONVIF.

## Чек-лист: что ещё нужно от пользователя

1. Приложение, к которому домофон привязан сейчас (Smart Life или Tuya Smart)?
2. Готов ли аккаунт Tuya Smart (регион Western Europe)?
3. Нужно ли событие звонка в HA (уведомления с кадром) или достаточно живого
   видео?

## Открытые вопросы

1. Появятся ли сущности звонка/детекции после привязки к Tuya Smart (зависит от
   DP-мэппинга конкретного устройства).
2. Стабильность WebRTC-потока go2rtc↔Tuya для этого OEM-устройства — проверить
   практикой.
