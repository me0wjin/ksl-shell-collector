#!/bin/bash

# ======================================
# Check collection quota per sign word
# New structure:
# data/dataset/<sign_word>/trial_<number>_<timestamp>/
# ======================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/settings.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] 설정 파일이 없습니다: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

WORD="${1:-}"

if [ -z "$WORD" ]; then
    echo "[ERROR] 사용법: check_quota.sh <sign_word>"
    exit 1
fi

SAFE_WORD=$(echo "$WORD" | tr ' /' '__')

DATASET_ROOT="$BASE_DIR/$SESSION_ROOT"
WORD_DIR="$DATASET_ROOT/$SAFE_WORD"

mkdir -p "$WORD_DIR"

CURRENT_COUNT=$(find "$WORD_DIR" -mindepth 1 -maxdepth 1 -type d -name "trial_*" | wc -l)

echo "======================================"
echo " 단어별 수집 상한선 점검"
echo "======================================"
printf "수어 종류       : %s\n" "$WORD"
printf "저장 폴더       : %s\n" "$WORD_DIR"
printf "현재 수집 개수  : %s / %s\n" "$CURRENT_COUNT" "$MAX_SAMPLES_PER_WORD"

if [ "$CURRENT_COUNT" -ge "$MAX_SAMPLES_PER_WORD" ]; then
    echo "[STOP] 이 수어 종류는 최대 수집 개수에 도달했습니다."
    echo "[GUIDE] 다른 수어 종류를 선택하거나 config/settings.conf에서 MAX_SAMPLES_PER_WORD 값을 조정하세요."
    exit 1
fi

REMAINING_COUNT=$((MAX_SAMPLES_PER_WORD - CURRENT_COUNT))
NEXT_TRIAL=$((CURRENT_COUNT + 1))

printf "남은 수집 가능 수: %s\n" "$REMAINING_COUNT"
printf "다음 촬영 회차   : trial_%03d\n" "$NEXT_TRIAL"
echo "[OK] 수집 가능"
