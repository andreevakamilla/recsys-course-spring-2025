#!/bin/bash
# =============================================================================
# run_all.sh — проверка ДЗ2
#
# Пайплайн:
#   [1] Проверяет Makefile + наличие analyze_ab.py
#   [2] make setup + make run  →  проверяет exit code и ab_result.json
#   [3] make run повторно      →  проверяет воспроизводимость (beat_control)
#   [4] score.py               →  GitHub API + дедлайн = балл
#
# Использование:
#   ./checker/run_all.sh \
#     --repo     /path/to/student/repo \
#     --pr       https://github.com/org/repo/pull/42 \
#     --deadline "2025-06-01T23:59:00+03:00" \
#     [--seed 31312] \
#     [--episodes 1000] \
#     [--k 0] \
#     [--token ghp_xxx]
# =============================================================================

set -euo pipefail

REPO=""; PR_URL=""; DEADLINE=""
SEED=31312; EPISODES=1000; K=0
TOKEN="${GITHUB_TOKEN:-}"
CHECKER_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)     REPO="$2";     shift 2 ;;
    --pr)       PR_URL="$2";   shift 2 ;;
    --deadline) DEADLINE="$2"; shift 2 ;;
    --seed)     SEED="$2";     shift 2 ;;
    --episodes) EPISODES="$2"; shift 2 ;;
    --k)        K="$2";        shift 2 ;;
    --token)    TOKEN="$2";    shift 2 ;;
    *) echo "Неизвестный аргумент: $1"; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$PR_URL" || -z "$DEADLINE" ]]; then
  echo "Использование: $0 --repo <path> --pr <url> --deadline <iso8601>"
  exit 1
fi

RESULTS_DIR="$CHECKER_DIR/results/$(basename "$REPO")_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
LOG="$RESULTS_DIR/check.log"
DATA_DIR="$RESULTS_DIR/data"
FAIL=0

log() { echo "$1" | tee -a "$LOG"; }

log "🔍 $(basename "$REPO")"
log "📁 Результаты: $RESULTS_DIR"
log ""

pip install requests -q

# =============================================================================
# [1] Проверка Makefile
# =============================================================================
log "══ [1/4] Makefile ══════════════════════"
python "$CHECKER_DIR/check_structure.py" "$REPO" 2>&1 | tee -a "$LOG" \
  || { log "❌ Стоп — исправь Makefile"; exit 1; }

# =============================================================================
# [2] Первый запуск
# =============================================================================
log ""
log "══ [2/4] Первый запуск ══════════════════"

cd "$REPO"
make setup 2>&1 | tee -a "$LOG"

AB1="$DATA_DIR/run1/ab_result.json"

if make run SEED="$SEED" EPISODES="$EPISODES" DATA_DIR="$DATA_DIR/run1" 2>&1 | tee -a "$LOG"; then

  # Проверяем наличие и формат ab_result.json
  if [[ -f "$AB1" ]]; then
    python3 -c "
import json, sys
r = json.load(open('$AB1'))
if 'beat_control' not in r:
    print('❌ ab_result.json: отсутствует поле beat_control')
    sys.exit(1)
print(f'✅ ab_result.json OK  beat_control={r[\"beat_control\"]}')
if 'lift_pct' in r and r['lift_pct'] is not None:
    print(f'   lift_pct={r[\"lift_pct\"]:+.2f}%  significant={r.get(\"significant\")}')
" 2>&1 | tee -a "$LOG" || ((FAIL++))
  else
    log "❌ ab_result.json не создан — analyze_ab.py не отработал или DATA_DIR неверный"
    ((FAIL++))
  fi
else
  log "❌ make run завершился с ошибкой"
  ((FAIL++))
fi

# =============================================================================
# [3] Второй запуск — воспроизводимость
# =============================================================================
log ""
log "══ [3/4] Воспроизводимость ══════════════"

make clean 2>&1 | tee -a "$LOG" || true
make setup 2>&1 | tee -a "$LOG"

AB2="$DATA_DIR/run2/ab_result.json"
REPRO="$RESULTS_DIR/repro_result.json"

if make run SEED="$SEED" EPISODES="$EPISODES" DATA_DIR="$DATA_DIR/run2" 2>&1 | tee -a "$LOG"; then
  if [[ -f "$AB1" && -f "$AB2" ]]; then
    python "$CHECKER_DIR/check_reproducibility.py" \
      --ab1 "$AB1" --ab2 "$AB2" --output "$REPRO" \
      2>&1 | tee -a "$LOG" || ((FAIL++))
  else
    log "❌ Один из ab_result.json не найден"
    ((FAIL++))
  fi
else
  log "❌ Второй make run завершился с ошибкой"
  ((FAIL++))
fi

# =============================================================================
# [4] Балл
# =============================================================================
log ""
log "══ [4/4] Балл ═══════════════════════════"

SCORE_ARGS=(--pr-url "$PR_URL" --deadline "$DEADLINE" --ab-result "$AB1" --k "$K")
[[ -n "$TOKEN" ]] && SCORE_ARGS+=(--token "$TOKEN")

python "$CHECKER_DIR/score.py" "${SCORE_ARGS[@]}" 2>&1 | tee -a "$LOG" || ((FAIL++))
cp score_result.json "$RESULTS_DIR/score_result.json" 2>/dev/null || true

# =============================================================================
# Итог
# =============================================================================
log ""
log "══════════════════════════════════════════"
[[ -f "$RESULTS_DIR/score_result.json" ]] && python3 -c "
import json
r = json.load(open('$RESULTS_DIR/score_result.json'))
beat = '✅ Победил' if r.get('beat_control') else '❌ Не победил'
sig  = '(значимо)' if r.get('significant') else '(незначимо)'
lift = f\"{r['lift_pct']:+.2f}%\" if r.get('lift_pct') is not None else 'N/A'
print(f'  {beat} контроль {sig},  lift={lift}')
print(f'  Балл: {r[\"score\"]} / {r[\"max_score\"]}  →  {r[\"formula\"]}')
" | tee -a "$LOG"
log "  Лог: $LOG"
log "══════════════════════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1