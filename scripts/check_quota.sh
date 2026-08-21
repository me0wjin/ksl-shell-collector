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

count_saved() {
    local trial_dir count=0 full_tsv
    if [ ! -d "$WORD_DIR" ]; then
        printf '0\n'
        return
    fi
    while IFS= read -r trial_dir; do
        full_tsv="$trial_dir/landmarks/full/all_landmarks.tsv"
        if [ -f "$trial_dir/raw/video.mp4" ] &&
            [ -f "$trial_dir/metadata.txt" ] &&
            [ -f "$full_tsv" ] &&
            [ "$(wc -l < "$full_tsv")" -gt 1 ] &&
            [ -f "$trial_dir/report/report.txt" ]; then
            count=$((count + 1))
        fi
    done < <(find "$WORD_DIR" -mindepth 1 -maxdepth 1 -type d -name 'trial_*' 2>/dev/null)
    printf '%s\n' "$count"
}

next_trial_number() {
    if [ ! -d "$WORD_DIR" ]; then
        printf '001\n'
        return
    fi
    find "$WORD_DIR" -mindepth 1 -maxdepth 1 -type d -name 'trial_*' -printf '%f\n' 2>/dev/null |
        awk -F_ '$2 ~ /^[0-9]+$/ { value=$2+0; if (value>max) max=value } END { printf "%03d", max+1 }'
}

CURRENT_COUNT=$(count_saved)

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
NEXT_TRIAL=$(next_trial_number)

printf "남은 수집 가능 수: %s\n" "$REMAINING_COUNT"
printf "다음 촬영 회차   : trial_%s\n" "$NEXT_TRIAL"
echo "[OK] 수집 가능"
