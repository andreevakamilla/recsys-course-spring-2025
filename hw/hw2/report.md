# ДЗ2 — Рекомендер WeightedHistory

## Abstract

Предложен рекомендер **WeightedHistory** на основе взвешенной агрегации
i2i-рекомендаций из истории прослушиваний пользователя.
В отличие от базового `I2IRecommender` из репо курса (один случайный якорь),
данный рекомендер собирает голоса от всех понравившихся треков в истории
и выбирает кандидата с наибольшим суммарным весом.
A/B эксперимент показал значимое улучшение `mean_time_per_session`
по сравнению с random-рекомендером (контроль).

## Детали реализации

### Схема

```
Пользователь → история (30 треков) → понравившиеся (time > 0.5)
                                            ↓
                               Топ-5 по времени прослушивания
                                            ↓
                               Для каждого → i2i-кандидаты (LightFM)
                                            ↓
                               Агрегация: candidate → сумма весов
                                            ↓
                               Топ-20 кандидатов + шум 15% → выбор
```

### Отличие от I2IRecommender из репо

| | I2IRecommender (репо) | WeightedHistory (наш) |
|---|---|---|
| Якорь | один, выбирается случайно с весами | все понравившиеся треки голосуют |
| Агрегация | первый подходящий кандидат | суммарный вес по всем источникам |
| Детерминизм | случайный выбор якоря | мягкий шум ±15% на финальный выбор |

### Файлы

```
botify/recommenders/weighted_history.py  — рекомендер
botify/experiment.py                     — WEIGHTED_HISTORY (HALF_HALF)
botify/server.py                         — C=random, T1=weighted_history
botify/config.json                       — без изменений (LightFM уже есть)
analyze_ab.py                            — A/B анализ
Makefile                                 — setup / run / clean
```

### Внешние зависимости

Никаких новых — используем `lightfm_i2i.jsonl` который уже есть в репо курса.

## Результаты A/B эксперимента

| metric                  | effect_pct | lower_pct | upper_pct | significant |
|-------------------------|------------|-----------|-----------|-------------|
| mean_time_per_session   | +28.4%     | +23.1%    | +33.7%    | True        |
| sessions                | +2.8%      | +0.2%     | +5.4%     | True        |
| mean_tracks_per_session | +13.2%     | +11.7%    | +14.7%    | True        |
| mean_request_latency    | -0.3%      | -0.4%     | -0.2%     | True        |
| time                    | +31.9%     | +27.2%    | +36.6%    | True        |

## Инструкция по запуску

### Требования

- Python 3.10+
- Docker + docker-compose
- Файл `botify/data/lightfm_i2i.jsonl` (уже в репо курса)

### Запуск

```bash
# Установка + старт сервиса
make setup

# Симуляция 30000 эпизодов + A/B анализ
make run SEED=31312 EPISODES=30000 DATA_DIR=./data

# Быстрая проверка (1000 эпизодов)
make run SEED=31312 EPISODES=1000 DATA_DIR=./data/quick

# Очистка
make clean
```

### Воспроизводимость

```bash
make run SEED=31312 EPISODES=1000 DATA_DIR=./data/run1
make clean && make setup
make run SEED=31312 EPISODES=1000 DATA_DIR=./data/run2
# run1 и run2 должны дать одинаковый знак effect_pct
```