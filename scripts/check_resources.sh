#!/bin/bash

# ======================================
# Check memory, disk, and CPU resources
# ======================================

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/settings.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] 설정 파일이 없습니다: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

get_free_memory_mb() {
    # free 명령어는 언어 환경에 따라 출력이 달라질 수 있으므로
    # /proc/meminfo에서 MemAvailable 값을 직접 읽는다.
    awk '/MemAvailable:/ { printf "%.0f", $2 / 1024 }' /proc/meminfo
}

get_free_disk_mb() {
    # 현재 프로젝트 폴더가 위치한 디스크의 남은 공간을 MB 단위로 확인한다.
    df -Pm "$BASE_DIR" | awk 'NR==2 {print $4}'
}

get_cpu_usage() {
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    prev_idle=$((idle + iowait))
    prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    sleep 0.3

    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    idle_now=$((idle + iowait))
    total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))

    total_diff=$((total_now - prev_total))
    idle_diff=$((idle_now - prev_idle))

    if [ "$total_diff" -eq 0 ]; then
        echo "0"
    else
        awk -v total="$total_diff" -v idle="$idle_diff" \
            'BEGIN { printf "%.0f", (100 * (total - idle) / total) }'
    fi
}

echo "======================================"
echo " 시스템 자원 점검"
echo "======================================"

FREE_MEMORY_MB=$(get_free_memory_mb)
FREE_DISK_MB=$(get_free_disk_mb)
CPU_USAGE_PERCENT=$(get_cpu_usage)

MEM_STATUS="OK"
DISK_STATUS="OK"
CPU_STATUS="OK"

if [ "$FREE_MEMORY_MB" -lt "$MIN_FREE_MEMORY_MB" ]; then
    MEM_STATUS="STOP"
fi

if [ "$FREE_DISK_MB" -lt "$MIN_FREE_DISK_MB" ]; then
    DISK_STATUS="STOP"
fi

if [ "$CPU_USAGE_PERCENT" -ge "$MAX_CPU_USAGE_PERCENT" ]; then
    CPU_STATUS="WARNING"
fi

printf "메모리 여유 공간 : %s MB / 기준 %s MB [%s]\n" "$FREE_MEMORY_MB" "$MIN_FREE_MEMORY_MB" "$MEM_STATUS"
printf "디스크 여유 공간 : %s MB / 기준 %s MB [%s]\n" "$FREE_DISK_MB" "$MIN_FREE_DISK_MB" "$DISK_STATUS"
printf "CPU 사용률       : %s%% / 경고 기준 %s%% [%s]\n" "$CPU_USAGE_PERCENT" "$MAX_CPU_USAGE_PERCENT" "$CPU_STATUS"

echo "======================================"

if [ "$MEM_STATUS" = "STOP" ]; then
    echo "[STOP] 사용 가능한 메모리가 부족합니다. 불필요한 프로그램을 종료한 뒤 다시 실행하세요."
    exit 1
fi

if [ "$DISK_STATUS" = "STOP" ]; then
    echo "[STOP] 저장 공간이 부족합니다. 불필요한 파일을 정리한 뒤 다시 실행하세요."
    exit 1
fi

if [ "$CPU_STATUS" = "WARNING" ]; then
    echo "[WARNING] 현재 CPU 사용률이 높습니다. 실행은 가능하지만 처리 속도가 느릴 수 있습니다."
fi

echo "[OK] 자원 점검 완료"
