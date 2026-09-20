# Шторы Babai CMB5 (`babai.curtain.cmb5`) и Home Assistant

Дата проверки: 2026-08-21.

## Вывод

Устройства с именами `babai-curtain-cmb5-mibt1669`, `babai-curtain-cmb5-mibt1E07`,
`babai-curtain-cmb5-mibtCC1E` — это три привода штор **Babai CMB5**, устройства
экосистемы Xiaomi/Mi Home: производитель 广州巴百信息 (Guangzhou Babai), тип
«CM智能窗帘（WiFi）», подключение **2,4 ГГц Wi-Fi** ([каталог miot-spec](https://home.miot-spec.com/s/babai.curtain.cmb5)).
Имена вида `<модель>-mibtXXXX` — это, судя по всему, DHCP-hostname устройств
(суффикс — последние байты MAC), как они отображаются в списке клиентов роутера
Keenetic; в Mi Home и Home Assistant те же устройства фигурируют как
`babai.curtain.cmb5` с суффиксом MAC (пример: `cover.babai_cmb5_04ee_motor_control`
при MAC `C4:93:BB:C3:04:EE` — [issue #2336](https://github.com/al-one/hass-xiaomi-miot/issues/2336)).

Подключить к Home Assistant **можно**, но только через экосистему Mi Home:

| Путь | Управление | Статус/позиция | Примечание |
|---|---|---|---|
| HACS [al-one/hass-xiaomi-miot](https://github.com/al-one/hass-xiaomi-miot), локальный режим | локально | ❌ прошивка отдаёт ошибку `-4004` | управление работает, статус нет |
| HACS [al-one/hass-xiaomi-miot](https://github.com/al-one/hass-xiaomi-miot), облачный режим | облако | ✅ | подтверждено владельцем интеграции |
| Официальная [XiaoMi/ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home) | облако | ✅ (только онлайн) | без интернета позиция не обновляется |

Полностью локальной схемы для этой модели сегодня нет: автор xiaomi-miot
классифицировал проблему как дефект прошивки и перевёл устройство на облачный
режим по умолчанию ([issue #2336, комментарий](https://github.com/al-one/hass-xiaomi-miot/issues/2336#issuecomment-2649850352)).

## Что это за устройство

- Модель в спецификации MIoT: `babai.curtain.cmb5`, URN
  `urn:miot-spec-v2:device:curtain:0000A00C:babai-cmb5:1`
  ([страница спецификации](https://home.miot-spec.com/s/babai.curtain.cmb5),
  атрибуты из [issue #2336](https://github.com/al-one/hass-xiaomi-miot/issues/2336)).
- Свойства по spec (видны в атрибутах сущностей):
  `curtain.motor_control` (открыть/закрыть/пауза), `curtain.target_position`,
  `curtain.current_position`, `curtain.mode`, `curtain.speed_level`,
  `curtain.fault`, переключатель `motor_reverse`.
- Продавец в РФ — карнизы Onviz (karniz-onviz.ru); модель заведена в российском
  хабе Sprut.hub ([issue #4174](https://github.com/sprut/Hub/issues/4174)).

## Варианты подключения

### Xiaomi Miot For Home Assistant (al-one) — рекомендуемый путь

Custom-интеграция из HACS. Устройство добавляется автоматически после входа в
аккаунт Mi Home; создаётся `cover` с управлением позицией. Нюансы:

- В локальном режиме свойства позиции возвращают `-4004 Other internal errors`,
  статус остаётся `unknown`; владелец интеграции подтвердил дефект прошивки и
  включил устройству облачный режим по умолчанию
  ([issue #2336](https://github.com/al-one/hass-xiaomi-miot/issues/2336)).
- После переключения на облако пользователь подтвердил полную работоспособность
  ([комментарий](https://github.com/al-one/hass-xiaomi-miot/issues/2336#issuecomment-2649870847)).

### Официальная интеграция Xiaomi Home

[XiaoMi/ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home) работает через
облако Xiaomi. Для родственной модели `babai.curtain.m515e` подтверждено:
без интернета управление работает, но обратная связь (текущая позиция) не
обновляется; issue закрыт как `wontfix`
([issue #1527](https://github.com/XiaoMi/ha_xiaomi_home/issues/1527)). То есть
официальный путь тоже облачный.

### Прямой BLE / другие протоколы

Неприменимо: устройство Wi-Fi, а не Bluetooth/Zigbee
([miot-spec](https://home.miot-spec.com/s/babai.curtain.cmb5)). Полностью
локального API у прошивки нет (см. выше). Если когда-нибудь потребуется полный
local-first, реалистичный вариант — замена приводов на Zigbee-модели.

## Рекомендация для этого хомлаба

1. Привязать все три привода к приложению Mi Home (Xiaomi Home).
2. Поставить HACS-интеграцию [al-one/hass-xiaomi-miot](https://github.com/al-one/hass-xiaomi-miot),
   войти в аккаунт Mi Home, убедиться, что устройства получили облачный режим
   (статус позиции обновляется).
3. Альтернатива — официальная [XiaoMi/ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home),
   если не хочется ставить кастомную интеграцию; ограничения те же (облако).

## Локальная настройка без облака (прогресс 2026-08-24)

Сделано на сервере homelab:

1. В HA (`/storage/apps/home-assistant/custom_components/`) установлены
   [HACS](https://github.com/hacs/integration) и
   [al-one/hass-xiaomi-miot](https://github.com/al-one/hass-xiaomi-miot) (master);
   HA перезапущен, healthy.
2. Найдены IP приводов (ARP по MAC из дампа Keenetic):

| Привод | MAC | IP |
|---|---|---|
| mibt1E07 | `b8:50:d8:f1:1e:07` | <device-ip> |
| mibt1669 | `b8:50:d8:f1:16:69` | <device-ip> |
| mibtCC1E | `b8:50:d8:ea:cc:1e` | <device-ip> |

3. Подтверждено в `config_flow.py` интеграции: есть режим **«Add device using
   host/token» (局域网集成)** — устройство добавляется по IP+токен, без аккаунта
   Xiaomi.

Блокирующий шаг — miio-токен каждого привода (протокол шифруется токеном,
локально устройство его не отдаёт в обычном состоянии). Варианты:

- **Без облака (экспериментально)**: ввести каждый привод в режим сопряжения
  (сброс, устройство поднимает свой AP) — в этом состоянии miio-дискавери
  отдаёт токен открыто; затем Wi-Fi-креды можно задать miio-командой
  `miIO.wifi_assoc` без приложения. Для прошивки Babai не проверено.
- **Однократный вход в Mi Home** (5 минут): токены достаются
  `xiaomi_miot.get_token` в HA или
  [Xiaomi Cloud Tokens Extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor);
  дальше интеграция работает по LAN (`miot_local: true`), облако больше не
  нужно для управления (статус позиции всё равно кривой локально из-за
  прошивки, см. выше).

Рекомендуемые пользователем действия на роутере: закрепить DHCP-резервы за
тремя MAC (текущие IP .40/.98/.135), чтобы локальные адреса не уплыли.

## Открытые вопросы

1. Подтвердить гипотезу про Keenetic: имена `babai-curtain-cmb5-mibtXXXX` взяты
   из списка клиентов роутера? (На схему подключения не влияет.)
2. Есть ли у пользователя аккаунт Mi Home (регион — Китай или другой)? От этого
   зависит выбор сервера при входе в интеграцию.
3. Приемлема ли зависимость статуса штор от облака Xiaomi, или в перспективе
   лучше менять приводы на Zigbee?
