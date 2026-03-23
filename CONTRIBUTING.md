# Contributing to Wire-Pod for Home Assistant

Спасибо за интерес к проекту! Вот как можно помочь:

## Сообщить о проблеме

1. Проверь существующие issues
2. Создай новый issue с тегом `[BUG]` или `[FEATURE]`
3. Включи логи и информацию о среде

## Pull Requests

1. Форкни репозиторий
2. Создай ветку: `git checkout -b feature/amazing-feature`
3. Закоммить изменения: `git commit -m 'Add amazing feature'`
4. Пуш: `git push origin feature/amazing-feature`
5. Открой Pull Request

## Структура проекта

```
wire-pod-addon/
├── config.yaml          # Конфигурация аддона
├── Dockerfile            # Сборка контейнера
├── run.sh                # Entrypoint
├── mqtt-bridge/          # Go код MQTT интеграции
│   ├── main.go
│   └── go.mod
├── nginx.conf            # Веб-прокси
├── repository.yaml       # Для HA Add-on Store
├── README.md             # Документация
└── .github/              # CI/CD и шаблоны

```

## Тестирование локально

```bash
# Сборка образа
docker build -t wire-pod-addon:test .

# Запуск
docker run --rm -it \
  -p 8080:8080 \
  -v $(pwd)/data:/data \
  wire-pod-addon:test
```

## Вопросы?

Создай issue или свяжись через GitHub Discussions.
