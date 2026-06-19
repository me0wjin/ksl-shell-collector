#!/bin/bash

# ======================================
# Split landmark TSV by body part
# ======================================

INPUT_TSV="$1"
OUTPUT_DIR="$2"

if [ -z "$INPUT_TSV" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "[ERROR] 사용법: split_by_part.sh <input_tsv> <output_dir>"
    exit 1
fi

if [ ! -f "$INPUT_TSV" ]; then
    echo "[ERROR] 입력 TSV 파일이 존재하지 않습니다: $INPUT_TSV"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

HEADER=$(head -n 1 "$INPUT_TSV")

for PART in pose face left_hand right_hand
do
    OUT_FILE="$OUTPUT_DIR/${PART}.tsv"

    echo "$HEADER" > "$OUT_FILE"

    awk -F'\t' -v part="$PART" 'NR > 1 && $3 == part { print }' "$INPUT_TSV" >> "$OUT_FILE"

    LINE_COUNT=$(wc -l < "$OUT_FILE")

    echo "[SPLIT] $PART -> $OUT_FILE"
    echo "[SPLIT] $PART 라인 수: $LINE_COUNT"
done

echo "[DONE] 부위별 TSV 분리 완료"
