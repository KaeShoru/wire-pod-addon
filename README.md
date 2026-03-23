# Wire-Pod for Home Assistant

[![GitHub Actions](https://github.com/KaeShoru/wire-pod-addon/actions/workflows/build.yml/badge.svg)](https://github.com/KaeShoru/wire-pod-addon/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Home Assistant Add-on для [Wire-Pod](https://github.com/kercre123/wire-pod) - бесплатного серверного ПО для робота Anki Vector.

## Возможности

- 🎙️ Голосовые команды Vector без подписки DDL
- 📊 MQTT интеграция с Home Assistant
- 🔋 Автоматическое обнаружение сенсоров (battery, status, WiFi)
- 🎮 Управление через MQTT команды
- 👁️ Изменение цвета глаз
- 🌐 Web интерфейс для настройки

## Требования

- Home Assistant OS или Supervised
- MQTT Broker (Mosquitto аддон рекомендуется)
- Anki Vector robot с активированным SDK

## Установка

### Через кастомный репозиторий

1. Открой **Settings** → **Add-ons** → **Add-on Store**
2. Нажми **⋮** (три точки) → **Repositories**
3. Добавь URL: `https://github.com/KaeShoru/wire-pod-addon`
4. Нажми **Add** → **Close**
5. Найди **Wire-Pod for Vector** в списке и установи

### Локальная установка

1. Скопируй папку `wire-pod-addon` в `/addons` на твоём Home Assistant
2. Перезагрузи Add-on Store
3. Найди в разделе "Local Add-ons"

## Конфигурация

### Обязательные настройки

| Опция | Описание | Пример |
|-------|----------|--------|
| `vector_esn` | ESN робота Vector | `006044c4` |
| `mqtt_broker_host` | Хост MQTT брокера | `core-mosquitto` |

### Дополнительные настройки

| Опция | Описание | По умолчанию |
|-------|----------|--------------|
| `stt_service` | Сервис распознавания речи (`vosk`/`whisper`/`leopard`) | `vosk` |
| `mqtt_discovery` | Авто-обнаружение сенсоров в HA | `true` |
| `telemetry_interval` | Интервал обновления (сек) | `30` |

## Использование

### Автоматически созданные сенсоры

После запуска в HA появятся:

- `sensor.vector_battery` — заряд батареи (%)
- `sensor.vector_status` — статус (idle/charging/on_charger/driving)
- `sensor.vector_wifi_signal` — уровень WiFi сигнала (dBm)
- `binary_sensor.vector_charging` — статус зарядки

### Отправка команд

```yaml
service: mqtt.publish
data:
  topic: homeassistant/vector/command
  payload: drive_forward
```

**Доступные команды:**
- `drive_forward` — ехать вперёд
- `drive_backward` — ехать назад
- `turn_left` — повернуть налево
- `turn_right` — повернуть направо
- `dock` — сесть на док-станцию
- `undock` — отъехать от док-станции
- `anim_hello` — приветственная анимация
- `beep` — издать звук

### Изменение цвета глаз

```yaml
service: mqtt.publish
data:
  topic: homeassistant/vector/set_eyes
  payload: '{"hue": 120, "saturation": 100, "intensity": 100}'
```

`hue`: 0-360 (цвет)
`saturation`: 0-100 (насыщенность)

## Примеры автоматизаций

```yaml
# Уведомление о разряде батареи
automation:
  - alias: "Vector Low Battery"
    trigger:
      platform: numeric_state
      entity_id: sensor.vector_battery
      below: 20
    action:
      service: notify.notify
      data:
        message: "🤖 Vector разряжен! Заряд: {{ states('sensor.vector_battery') }}%"

  # Отправка на зарядку ночью
  - alias: "Vector Auto Dock"
    trigger:
      platform: time
      at: "23:00:00"
    condition:
      condition: numeric_state
      entity_id: sensor.vector_battery
      below: 50
    action:
      service: mqtt.publish
      data:
        topic: homeassistant/vector/command
        payload: dock

  # Приветствие при возвращении домой
  - alias: "Vector Welcome Home"
    trigger:
      platform: state
      entity_id: person.alexander
      to: "home"
    action:
      service: mqtt.publish
      data:
        topic: homeassistant/vector/command
        payload: anim_hello
```

## Устранение неполадок

### Vector не подключается

1. Убедись что Vector активирован с SDK через `vector-auth` или Wire-Pod
2. Проверь ESN в настройках аддона (без пробелов, регистр не важен)
3. Vector и Home Assistant должны быть в одной сети
4. Проверь логи аддона в разделе **Logs**

### MQTT не работает

1. Убедись что Mosquitto установлен: **Settings** → **Devices & Services** → **MQTT**
2. Если используешь внешний брокер — проверь host/port/credentials
3. Включи `mqtt_discovery: true` для автоматического создания сенсоров

## Благодарности

- [kercre123](https://github.com/kercre123) — Wire-Pod
- [Digital Dream Labs](https://github.com/digital-dream-labs) — открытый исходный код Chipper
- [fforchino](https://github.com/fforchino) — vector-go-sdk

## Лицензия

MIT License — см. [LICENSE](LICENSE)

## Дисклеймер

Этот проект не связан с Digital Dream Labs или Anki. Anki Vector — торговая марка Anki, Inc.
