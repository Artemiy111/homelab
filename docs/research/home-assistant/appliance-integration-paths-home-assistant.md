# Подключение стиральной/сушильной машин и посудомойки к Home Assistant

> Источники: документация интеграций Home Assistant (home-assistant.io), GitHub-репозитории HACS-проектов, форум community.home-assistant.io.
> Дата проверки: 2026-08-21.

## Вывод

Путь подключения определяется **брендом**, а не типом машины: у большинства крупных производителей есть фирменное приложение + облачный API, для которого существует либо официальная интеграция HA core, либо зрелая HACS-интеграция. Практически все они дают **статус программы, остаточное время и уведомление о конце цикла**; дистанционный старт есть не у всех и часто требует включения «Remote Start» на самой машине.

Итоговая карта решений:

| Ситуация | Решение |
|---|---|
| Samsung | HA core `SmartThings` — но с **октября 2026 API станет платным** (~$4.99/мес) |
| LG | HA core `LG ThinQ` (новые модели) или HACS `SmartThinQ Sensors` (старые) |
| Bosch/Siemens | HA core `Home Connect` |
| Miele | HA core `Miele` |
| Electrolux/AEG | HACS Default `Electrolux` (TTLucian/ha-electrolux) |
| Haier/Candy/Hoover | HACS Default `Haier hOn` (Andre0512/hon); **приложение Haier Evo (РФ) не поддерживается** |
| Beko/Grundig | HACS Default `HomeWhiz` (есть даже локальный BLE-вариант без облака) |
| Gorenje/Hisense | HACS `ConnectLife` (oyvindwe/connectlife-ha), для РФ — экспериментальная опция TRIR |
| Whirlpool/Maytag | HA core `Whirlpool Appliances` |
| Hotpoint-Ariston/Indesit, Vestel, «без WiFi» | **Умная розетка с учётом энергии** (fallback) |

Розетка с измерением энергии — универсальный fallback: по профилю потребления детектируется конец цикла готовым blueprint'ом сообщества. IR-пульты и Zigbee-реле для стиралок/посудомоек **не подходят**: у машин нет ИК-приёмника, а размыкание реле на нагрузке 2–3 кВт во время цикла опасно и ничего не сообщает о состоянии.

---

## Алгоритм определения пути подключения

Шаги выполнять по порядку для каждой машины после того, как придут фото:

### Шаг 1. Определить бренд и модель

- Бренд — логотип на фронтальной панели или на шильдике.
- Точная модель (PNC/код изделия) — на шильдике за люком/дверцей или сзади. Для Electrolux/AEG ключевой идентификатор — **PNC (Product Number Code)**, именно он используется в каталоге моделей интеграции ([ha-electrolux README](https://github.com/TTLucian/ha-electrolux)).
- Страна сборки не важна — важен только бренд и то, в какое приложение машина регистрируется.

### Шаг 2. Проверить наличие WiFi-модуля и фирменного приложения

Признаки на фото/в спецификации модели:

- логотип WiFi на панели управления;
- упоминание фирменного приложения в мануале: SmartThings (Samsung), LG ThinQ (LG), Home Connect (Bosch/Siemens), Miele@mobile (Miele), hOn (Haier/Candy/Hoover), HomeWhiz (Beko/Grundig), ConnectLife (Gorenje/Hisense), My Electrolux Care / My AEG Care (Electrolux/AEG);
- QR-код на панели/в дверце, ведущий в приложение.

Если WiFi-модуля нет — сразу путь «розетка» (шаг 4).

### Шаг 3. Проверить наличие интеграции HA

1. Официальные интеграции: искать бренд в списке [home-assistant.io/integrations](https://www.home-assistant.io/integrations/) (core-интеграции ставятся без HACS).
2. HACS-интеграции: поиск по [HACS default repository](https://github.com/hacs/default/blob/main/data/store/integration_data.json) и по GitHub.
3. Свериться с таблицей ниже — там только проверенные первоисточники.

### Шаг 4. Fallback — умная розетка с измерением энергии

Если интеграции нет (или API платный/регион не поддерживается): розетка с энергомониторингом (Zigbee/WiFi, 16 А) + автоматизация определения конца цикла по мощности. См. раздел [Fallback](#fallback-умная-розетка-с-учётом-энергии).

### Шаг 5. Что НЕ подходит

- **IR (ИК)-управление** — у стиральных/сушильных машин и посудомоек нет ИК-приёмника; ИК работает только для ТВ/кондиционеров.
- **Zigbee/Z-Wave реле на питание** — обесточивать машину под нагрузкой во время цикла опасно (ТЭН, насос), а статус цикла реле не даёт. Допустимо только как аварийное отключение воды/розетки, не как канал управления.
- **Датчик вибрации/открытия двери** — даёт шумные ложные срабатывания (отжим ≠ конец стирки); годится максимум как грубая эвристика, не как основной путь.

---

## Пути подключения по брендам

Все строки проверены по первоисточникам 2026-08-21. «Core» = встроенная интеграция HA, «HACS» = кастомная интеграция через Home Assistant Community Store.

| Бренд | Приложение | Способ | Что даёт | Первоисточник |
|---|---|---|---|---|
| **Samsung** | SmartThings | Core (`smartthings`, Cloud Push) | Состояние машины/сушки/посудомойки (`washerOperatingState`: machine state, job state, **completion time**), режимы, remote start, датчики энергии. ⚠️ **С октября 2026 Samsung переводит SmartThings API на платную подписку Personal Plan $4.99/мес** — предупреждение прямо в доках HA | [HA docs](https://www.home-assistant.io/integrations/smartthings/), [анонс SmartThings](https://community.smartthings.com/t/a-new-enhanced-smartthings-api-experience/309947) |
| **LG** | LG ThinQ | Core (`lg_thinq`, с HA 2024.11) + HACS-альтернатива | Core через ThinQ Connect API (PAT-токен с [connect-pat.lgthinq.com](https://connect-pat.lgthinq.com)): текущий статус, **remaining time / total time**, события `washing_is_complete`, `drying_is_complete`, `cleaning_is_complete`, ошибки, история энергопотребления, старт/пауза. Старые модели, которых нет в Connect API — через HACS | [HA docs](https://www.home-assistant.io/integrations/lg_thinq/); HACS: [ollo69/ha-smartthinq-sensors](https://github.com/ollo69/ha-smartthinq-sensors) (1323★, washer/dryer/dishwasher в topics) |
| **Bosch / Siemens** (+ Neff, Gaggenau) | Home Connect | Core (`home_connect`, Cloud Push) | Operation state (`run`/`finished`/...), **program progress %, finish time**, события `Program finished` / `Drying process finished`, выбор и запуск программ, door state. Нужен бесплатный девелоперский аккаунт на developer.home-connect.com | [HA docs](https://www.home-assistant.io/integrations/home_connect/) |
| **Miele** | Miele app (Miele@home) | Core (`miele`, с HA 2025.5, Platinum quality) | Status, Program, Program phase, **Remaining time**, Finish, расход энергии/воды за цикл, старт/пауза/стоп; в доках есть готовый пример автоматизации «Notify when program ends». Машины должны быть WiFiConn@ct (или через шлюз XGW3000) | [HA docs](https://www.home-assistant.io/integrations/miele/) |
| **Electrolux / AEG** (+ Frigidaire, Zanussi*) | My Electrolux Care / My AEG Care / Electrolux Life | HACS Default ([TTLucian/ha-electrolux](https://github.com/TTLucian/ha-electrolux)) | Через официальный Electrolux Group Developer API (нужны бесплатные креды на [developer.electrolux.one](https://developer.electrolux.one/dashboard)): applianceState (**END_OF_CYCLE**), фаза цикла, **time-to-end**, выбор программы, соль/ополаскиватель, старт/пауза. Каталог Full для WM/TD/DW/WD. *Zanussi формально тоже группа Electrolux — зависит от приложения модели | [README репозитория](https://github.com/TTLucian/ha-electrolux) |
| **Haier / Candy / Hoover** | hOn (Candy simply-Fi — только новые модели) | HACS Default ([Andre0512/hon](https://github.com/Andre0512/hon), 1518★) | Программа, фаза, **remaining time**, дверь, старт/пауза/стоп, учёт электроэнергии и воды за цикл. ⚠️ История: Haier пыталась удалить проект (takedown 2024), проект выжил через форки. ⚠️ **Для РФ важно: машины Haier с приложением Haier Evo НЕ поддерживаются** (таблица совместимости в README); Candy simply-Fi старых моделей — отдельный проект [ofalvai/home-assistant-candy](https://github.com/ofalvai/home-assistant-candy) (169★) | [README hon](https://github.com/Andre0512/hon) |
| **Beko / Grundig** (+ Arcelik, Bauknecht) | HomeWhiz | HACS Default ([home-assistant-HomeWhiz/home-assistant-HomeWhiz](https://github.com/home-assistant-HomeWhiz/home-assistant-HomeWhiz), 151★) | Мониторинг и управление **по локальному Bluetooth или через облако HomeWhiz (WiFi)** — в зависимости от модели. Есть и ESPHome-BLE вариант ([mateuszsikora/esphome-homewhiz](https://github.com/mateuszsikora/esphome-homewhiz)) | [README репозитория](https://github.com/home-assistant-HomeWhiz/home-assistant-HomeWhiz) |
| **Gorenje / Hisense** (+ Asko*) | ConnectLife (в РФ — ConnectLife.TRIR) | HACS ([oyvindwe/connectlife-ha](https://github.com/oyvindwe/connectlife-ha), 291★) | Маппинги для стиральных (типы 025/027), сушильных (030/032), посудомоек (015); дневные сенсоры энергии и воды; опрос раз в 60 сек. ⚠️ Для РФ/СНГ с приложением ConnectLife.TRIR — включить экспериментальную опцию «TRIR» при настройке | [README репозитория](https://github.com/oyvindwe/connectlife-ha) |
| **Whirlpool / Maytag / KitchenAid** | Whirlpool app | Core (`whirlpool`, с HA 2022.10, Silver) | Sensor: machine state, **time remaining**, tank status; binary sensor двери. Подтверждённые модели — US; европейские/российские Hotpoint-Ariston и Indesit (тоже группа Whirlpool) официально не заявлены — проверять регистрацию машины в Whirlpool app | [HA docs](https://www.home-assistant.io/integrations/whirlpool/) |
| **Hotpoint-Ariston / Indesit** | — (нет актуального приложения для стиралок в РФ) | Нет подходящей интеграции → **розетка** | Все GitHub-проекты «ariston» (например [fustom/ariston-remotethermo-home-assistant-v3](https://github.com/fustom/ariston-remotethermo-home-assistant-v3), 282★) — это **водонагреватели** (RemoteThermo), не стиральные машины. Единственный шанс — если конкретная модель регистрируется в Whirlpool app (см. строку выше) | [поиск по GitHub](https://github.com/search?q=ariston+home+assistant&type=repositories) |
| **Vestel** | Vestel Akıllı Yaşam / HomeVSmart | Нет интеграции для стиралок → **розетка** | Существуют только кастомные интеграции для кондиционеров Vestel (например [fatboytr/Vestel-AC-HomeAssistant](https://github.com/fatboytr/Vestel-AC-HomeAssistant)); стиральные/сушильные/посудомоечные машины Vestel интеграций не имеют | [поиск по GitHub](https://github.com/search?q=vestel+home+assistant&type=repositories) |
| **Xiaomi / Mijia** | Mi Home | HACS ([al-one/hass-xiaomi-miot](https://github.com/al-one/hass-xiaomi-miot), 6083★) | Автоматическая интеграция всех Xiaomi-устройств через miot-spec (WiFi/BLE/Zigbee), включая стиральные машины: статусы, остаточное время — набор сущностей зависит от spec конкретной модели. Core-интеграция `xiaomi_miio` стиралки полноценно не покрывает | [README репозитория](https://github.com/al-one/hass-xiaomi-miot) |

\* — бренды одной группы, но поддержка зависит от того, в какое приложение реально регистрируется конкретная модель.

---

## Fallback: умная розетка с учётом энергии

Подходит любой машине (нет WiFi-модуля, платный/недоступный API, экзотический бренд). Даёт: **детект начала и конца цикла, потребление кВт·ч на цикл, уведомления**. Не даёт: номер программы, остаточное время, дистанционный старт.

### Какие сущности даёт HA

Умная розетка с измерениями (Zigbee — например на базе Lidl/Aqara/Tuya Zigbee, или WiFi — Shelly Plug S / Tuya с прошивкой tuya-local) создаёт в HA:

- `sensor.*_power` — текущая мощность, Вт (`device_class: power`);
- `sensor.*_energy` — накопленное потребление, кВт·ч (`device_class: energy`, годится для Energy Dashboard);
- `switch`/`light`-подобная сущность самого реле (использовать только для обесточивания ПОСЛЕ конца цикла, не для управления).

Требование к розетке: **номинал ≥16 А (3500+ Вт)** — ТЭН стиральной машины и особенно сушильной может тянуть 2–3 кВт длительно.

### Типовая автоматизация «конец стирки»

Классический blueprint сообщества — [«Notify or do something when an appliance like a dishwasher or washing machine finishes»](https://community.home-assistant.io/t/notify-or-do-something-when-an-appliance-like-a-dishwasher-or-washing-machine-finishes/254841) от Sbyx ([код-blueprint в gist](https://gist.github.com/sbyx/6d8344d3575c9865657ac51915684696)). Логика двухфазная:

1. **Старт цикла**: мощность поднялась выше порога (например >10 Вт) и держится N минут — считаем, что цикл начался (защита от ложных срабатываний при перезагрузке HA).
2. **Конец цикла**: мощность упала ниже порога (например <5–10 Вт) и держится M минут подряд (обычно 2–6 мин) — цикл завершён, выполняем действия (push-уведомление, TTS, свет в ванной).

Пороги и тайминги подбираются по фактическому профилю: у стиралки паузы на замачивании/сливе дают провалы мощности, поэтому «держится ниже порога M минут» обязательно; у сушильной машины с тепловым насосом профиль ровнее, у конденсационной с ТЭНом — пилообразный. Второй популярный blueprint с тем же принципом: [Appliance Notifications & Actions](https://community.home-assistant.io/t/appliance-notifications-actions-washing-machine-clothes-dryer-dish-washer-etc/650166).

Для подсчёта кВт·ч за цикл: сбрасываемый счётчик через `utility_meter` (cycle: daily не нужен — достаточно суммировать дельту `sensor.*_energy` между триггерами «старт» и «конец») либо шаблонный счётчик циклов.

Ограничения fallback'а: не видно, какая программа идёт и сколько осталось; ложное «окончание» возможно при длинной паузе программы; розетка сама становится точкой отказа — машину нельзя эксплуатировать в режиме, где розетка регулярно рвёт питание.

---

## Чек-лист: что нужно от фото устройства

Когда придут фото стиральной, сушильной и посудомоечной машин, снять с каждого фото:

1. **Бренд** — логотип на передней панели (крупно).
2. **Полное название модели** — с шильдика (за люком/дверцей или сзади): модель + серийник + код изделия (для Electrolux/AEG критичен PNC — 9 цифр).
3. **Панель управления крупным планом** — ищем:
   - значок WiFi / надпись WiFi;
   - QR-код фирменного приложения;
   - надписи типа «SmartThings», «ThinQ», «Home Connect», «hOn», «HomeWhiz», «ConnectLife».
4. **Скриншот из мануала/спецификации** (если есть) — раздел «подключение к приложению».
5. Страна сборки — **не нужна** (не влияет на выбор пути).

По этим данным идём по таблице раздела «Пути подключения по брендам»: бренд → приложение → способ (core/HACS/розетка).

---

## Открытые вопросы

1. **Бренды и модели трёх машин** — главная неизвестная; от них зависит весь план (фото ожидаются).
2. Есть ли у конкретных моделей WiFi-модуль (часто даже внутри одного бренда WiFi есть только у части линеек)?
3. Если Haier — какое приложение используется в РФ: hOn или **Haier Evo**? Evo не поддерживается интеграцией hOn → тогда сразу розетка.
4. Если Gorenje/Hisense — приложение ConnectLife или ConnectLife.TRIR (для TRIR нужна экспериментальная опция)?
5. Готовность платить за SmartThings Personal Plan (~$4.99/мес с октября 2026), если среди машин окажется Samsung, либо согласие на розетку вместо нативной интеграции?
6. Есть ли уже в доме умные розетки с энергомониторингом (и какой протокол — Zigbee/WiFi), или их надо докупать? Сколько розеток нужно (по одной на машину = 3 шт.)?
7. Целевая функциональность: достаточно ли уведомления «цикл завершён» (хватит розетки), или нужны остаточное время/выбор программы (нужна нативная интеграция)?
8. Какой хаб Zigbee уже есть в HA (влияет на выбор розеток)?
