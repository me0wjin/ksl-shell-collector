#!/bin/bash

# ======================================
# Make report for landmark collection result
# ======================================

SESSION_ID="$1"
VIDEO_PATH="$2"
ALL_TSV="$3"
PART_DIR="$4"
REPORT_DIR="$5"

if [ -z "$SESSION_ID" ] || [ -z "$VIDEO_PATH" ] || [ -z "$ALL_TSV" ] || [ -z "$PART_DIR" ] || [ -z "$REPORT_DIR" ]; then
    echo "[ERROR] 사용법: make_report.sh <session_id> <video_path> <all_tsv> <part_dir> <report_dir>"
    exit 1
fi

if [ ! -f "$ALL_TSV" ]; then
    echo "[ERROR] 전체 TSV 파일이 존재하지 않습니다: $ALL_TSV"
    exit 1
fi

if [ ! -d "$PART_DIR" ]; then
    echo "[ERROR] 부위별 결과 폴더가 존재하지 않습니다: $PART_DIR"
    exit 1
fi

mkdir -p "$REPORT_DIR"

VIDEO_NAME=$(basename "$VIDEO_PATH")
ALL_TSV_NAME=$(basename "$ALL_TSV")
REPORT_FILE="$REPORT_DIR/${SESSION_ID}_${VIDEO_NAME}_report.txt"

TOTAL_LINES=$(wc -l < "$ALL_TSV")
FRAME_COUNT=$(awk -F'\t' 'NR > 1 { print $2 }' "$ALL_TSV" | sort -n | uniq | wc -l)

{
    echo "======================================"
    echo " KSL Data Collection Report"
    echo "======================================"
    echo "Session ID      : $SESSION_ID"
    echo "Video Name      : $VIDEO_NAME"
    echo "Generated Time  : $(date)"
    echo ""
    echo "[Input / Output]"
    echo "Input Video     : $VIDEO_PATH"
    echo "All TSV File    : $ALL_TSV_NAME"
    echo "Part Directory  : $PART_DIR"
    echo ""
    echo "[Summary]"
    echo "Total TSV Lines : $TOTAL_LINES"
    echo "Frame Count     : $FRAME_COUNT"
    echo ""
    echo "[Part Files]"
    for PART in pose face left_hand right_hand
    do
        PART_FILE="$PART_DIR/${PART}.tsv"

        if [ -f "$PART_FILE" ]; then
            PART_LINES=$(wc -l < "$PART_FILE")
            echo "$PART : $PART_LINES lines"
        else
            echo "$PART : missing"
        fi
    done
    echo ""
    echo "[Status]"
    echo "Result : SUCCESS"
    echo "======================================"
} > "$REPORT_FILE"

echo "[REPORT] 리포트 생성 완료: $REPORT_FILE"
