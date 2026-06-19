#!/bin/bash

# ======================================
# Validate generated landmark TSV files
# ======================================

INPUT_TSV="$1"
PART_DIR="$2"

if [ -z "$INPUT_TSV" ] || [ -z "$PART_DIR" ]; then
    echo "[ERROR] 사용법: validate_result.sh <input_tsv> <part_dir>"
    exit 1
fi

echo "[VALIDATE] 결과 검증 시작"

# 1. 전체 TSV 파일 존재 확인
if [ ! -f "$INPUT_TSV" ]; then
    echo "[ERROR] 전체 TSV 파일이 존재하지 않습니다: $INPUT_TSV"
    exit 1
fi

# 2. 전체 TSV 라인 수 확인
TOTAL_LINES=$(wc -l < "$INPUT_TSV")

if [ "$TOTAL_LINES" -le 1 ]; then
    echo "[ERROR] 전체 TSV에 데이터가 없습니다."
    exit 1
fi

echo "[VALIDATE] 전체 TSV 파일 확인 완료"
echo "[VALIDATE] 전체 TSV 라인 수: $TOTAL_LINES"

# 3. 부위별 결과 폴더 존재 확인
if [ ! -d "$PART_DIR" ]; then
    echo "[ERROR] 부위별 결과 폴더가 존재하지 않습니다: $PART_DIR"
    exit 1
fi

echo "[VALIDATE] 부위별 결과 폴더 확인 완료: $PART_DIR"

# 4. 부위별 TSV 파일 확인
for PART in pose face left_hand right_hand
do
    PART_FILE="$PART_DIR/${PART}.tsv"

    if [ ! -f "$PART_FILE" ]; then
        echo "[ERROR] $PART 파일이 존재하지 않습니다: $PART_FILE"
        exit 1
    fi

    PART_LINES=$(wc -l < "$PART_FILE")

    if [ "$PART_LINES" -le 1 ]; then
        echo "[WARNING] $PART 파일에 데이터가 없습니다. 헤더만 존재합니다."
    else
        echo "[VALIDATE] $PART 파일 확인 완료: $PART_LINES lines"
    fi
done

# 5. 전체 TSV에서 프레임 수 계산
FRAME_COUNT=$(awk -F'\t' 'NR > 1 { print $2 }' "$INPUT_TSV" | sort -n | uniq | wc -l)

echo "[VALIDATE] 총 프레임 수: $FRAME_COUNT"

if [ "$FRAME_COUNT" -eq 0 ]; then
    echo "[ERROR] 프레임 데이터가 없습니다."
    exit 1
fi

echo "[VALIDATE] 결과 검증 완료"
