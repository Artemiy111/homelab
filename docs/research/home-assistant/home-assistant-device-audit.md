# Аудит умных устройств дома: подключение к Home Assistant

Дата проверки: 2026-08-21.

## Вывод

Все умные устройства дома подключаемы. Три машины Midea закрываются одной
HACS-интеграцией (облачной или локальной), сушилка Hisense/Gorenje —
ConnectLife-интеграцией, шторы Babai — через экосистему Mi Home (статус только
через облако Xiaomi), домофон Novihome — через go2rtc и аккаунт Tuya Smart.
Инвентаризация сверена с дампом конфига роутера Keenetic Viva от 2026-08-21:
имена хостов Midea (`midea-db-*`, `midea-ca-*`, `midea-e1-*`) совпадают с кодами
типов протокола Midea (DB — стиралка, CA — холодильник, E1 — посудомойка), что
дополнительно подтверждает выбор интеграций.

| Устройство | Идентификация | Путь подключения | Статус |
|---|---|---|---|
| Стиральная машина | Midea MF200W90WB/S-RU, приложение MSmartHome; в сети видна как `midea-db-0140` (тип `DB` подтверждён) | HACS Default [sususweet/midea_auto_cloud](https://github.com/sususweet/midea_auto_cloud) — тип `T0xDB` (облако) или [Cyborg2017/midea_smart_home](https://github.com/Cyborg2017/midea_smart_home) — `0xDB` (локально после разовой авторизации) | ✅ подтверждено |
| Сушильная машина | **Hisense**, приложение ConnectLife подтверждено наклейками на машине («Connect Life», QR «Scan to Download APP»); Batch D50N5, SN `1WK080206E0FD50N5120321`. Префикс SN `1WK08…` совпадает с форматом feature-кодов ConnectLife (`030-1wk…` — сушилки) | HACS [oyvindwe/connectlife-ha](https://github.com/oyvindwe/connectlife-ha): сушилки — тип `030`, при отсутствии точного маппинга варианта работает generic-словарь `030.yaml`; ⚠️ в 0.46.0 был регресс с недоступными сущностями Hisense ([issue #651](https://github.com/oyvindwe/connectlife-ha/issues/651)) — при проблемах откатиться на 0.29.0 | ✅ подтверждено; точная модель с шильдика желательна, но не блокирует |
| Посудомоечная машина | Midea MID60S720i, встраиваемая; в сети видна как `midea-e1-0004` (тип `E1` подтверждён) | как стиралка: `T0xE1` / `0xE1` | ✅ подтверждено |
| Холодильник | Midea MDRM691MIE28, наклейка Smart Home/MSmartHome; в сети виден как `midea-ca-0124` (тип `CA` подтверждён) | как стиралка: `T0xCA` / `0xCA` | ✅ подтверждено |
| Микроволновая печь | Midea, в сети Keenetic не присутствует → Wi-Fi-модуля нет (у Midea «умные» СВЧ имели бы хост вида `midea-b0/bf-*`) | интеграция невозможна по воздуху; опционально розетка с энергомониторингом | ➖ не сетевое устройство |
| Принтер | OKI (хост `printer C610-DC7997`, OUI `00:80:87` — OKI Electric; похоже на модель C610), Ethernet, DHCP .96 | в HA как «умное устройство» не интегрируется; опционально мониторинг статуса/тонера через SNMP-сенсоры | ➖ вне рамок умного дома |
| Приводы штор ×3 | Babai CMB5 (`babai.curtain.cmb5`, Wi-Fi, Mi Home); MAC из дампа (`b8:50:d8:f1:16:69`, `b8:50:d8:f1:1e:07`, `b8:50:d8:ea:cc:1e`) — суффиксы имён совпадают с хвостом MAC | [al-one/hass-xiaomi-miot](https://github.com/al-one/hass-xiaomi-miot) или официальная [XiaoMi/ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home); статус позиции — только через облако Xiaomi | ✅ с оговоркой, см. [babai-curtain-cmb5-home-assistant.md](babai-curtain-cmb5-home-assistant.md) |
| Видеодомофон | Novihome COMFY 10 FHD WIFI KIT DARK v.4102; приложения Smart Life/Tuya Smart (официальная карточка товара), прошивка NOVIGUI, Cloud ID, единственный открытый порт TCP 6668 — платформа Tuya; DHCP-резерв .200 | go2rtc (v1.9.13+) источник Tuya через аккаунт **Tuya Smart** → WebRTC-поток в HA/Frigate с двусторонним звуком; локального RTSP нет | ✅ путь подтверждён, см. [intercom-camera-home-assistant.md](intercom-camera-home-assistant.md) |

Общий справочник по бытовой технике (алгоритм выбора пути, таблица брендов,
fallback через розетку с энергомониторингом):
[appliance-integration-paths-home-assistant.md](appliance-integration-paths-home-assistant.md).

## Порядок внедрения

1. **Midea ×3**: установить одну интеграцию ([midea_auto_cloud](https://github.com/sususweet/midea_auto_cloud)
   — проще и в HACS Default; [midea_smart_home](https://github.com/Cyborg2017/midea_smart_home)
   — если важен локальный контур управления), войти аккаунтом MSmartHome.
2. **Сушилка**: снять модель с шильдика, поставить connectlife-ha.
3. **Шторы**: привязать к Mi Home → hass-xiaomi-miot.
4. **Домофон**: привязать к Tuya Smart (если сейчас в Smart Life — перепривязать),
   затем go2rtc → Add → Tuya.

## Открытые вопросы

1. Регион аккаунтов: пользователь ожидает РФ или Китай. Оба варианта покрыты:
   [midea_auto_cloud](https://github.com/sususweet/midea_auto_cloud) работает и с
   MSmartHome, и с китайской Meiju (美的美居); сервер Mi Home выбирается при входе
   в интеграцию Xiaomi. Уточнить фактический регион на этапе настройки.
2. Точная модель сушилки (шильдик внутри двери/сзади) — для сверки маппинга
   `030-…` в connectlife-ha; не блокирует подключение.
3. Домофон: в каком приложении привязан сейчас (Smart Life/Tuya Smart) и есть ли
   аккаунт Tuya Smart (регион Western Europe).
4. Есть ли Zigbee-хаб и умные розетки с энергомониторингом (для fallback и
   будущих датчиков).
