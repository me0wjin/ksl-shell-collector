#!/bin/bash

# Sync:Us Collector - shell-driven Korean Sign Language data recorder

set -uo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/settings.conf"
CATALOG_FILE="$BASE_DIR/config/sign_catalog.tsv"

if [ ! -f "$CONFIG_FILE" ]; then
    printf '[ERROR] 설정 파일이 없습니다: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

MAX_SAMPLES_PER_WORD="${MAX_SAMPLES_PER_WORD:-5}"
SESSION_ROOT="${SESSION_ROOT:-data/dataset}"
CAMERA_WARMUP_SECONDS="${CAMERA_WARMUP_SECONDS:-3}"
PREVIEW_MIRROR_ENABLED="${PREVIEW_MIRROR_ENABLED:-true}"
VIDEO_MIRROR_ENABLED="${VIDEO_MIRROR_ENABLED:-false}"
RECORD_COUNTDOWN_SECONDS=3

VENV_PYTHON="$BASE_DIR/.venv/bin/python"
RECORD_PY="$BASE_DIR/python/record_video.py"
RUN_PIPELINE="$BASE_DIR/scripts/run_pipeline.sh"
VALIDATE_RESULT="$BASE_DIR/scripts/validate_result.sh"
CHECK_RESOURCES="$BASE_DIR/scripts/check_resources.sh"

INPUT_DIR="$BASE_DIR/input_videos"
ARCHIVE_DIR="$INPUT_DIR/archive"
DATASET_ROOT="$BASE_DIR/$SESSION_ROOT"

if [ ! -f "$CATALOG_FILE" ]; then
    printf '[ERROR] 동작 catalog 파일이 없습니다: %s\n' "$CATALOG_FILE" >&2
    exit 1
fi

mkdir -p "$INPUT_DIR" "$ARCHIVE_DIR" "$DATASET_ROOT"

COLOR_ENABLED=0
if command -v tput >/dev/null 2>&1 && [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ]; then
    if tput colors >/dev/null 2>&1; then
        COLOR_ENABLED=1
        C_TITLE="$(tput setaf 6)$(tput bold)"
        C_OK="$(tput setaf 2)"
        C_WARN="$(tput setaf 3)"
        C_ERR="$(tput setaf 1)"
        C_RESET="$(tput sgr0)"
    fi
fi

: "${C_TITLE:=}"
: "${C_OK:=}"
: "${C_WARN:=}"
: "${C_ERR:=}"
: "${C_RESET:=}"

clear_screen() {
    if [ "$COLOR_ENABLED" -eq 1 ]; then
        tput clear
    elif [ -t 1 ] && command -v clear >/dev/null 2>&1; then
        clear 2>/dev/null || printf '\n'
    fi
}

safe_name() {
    printf '%s' "$1" | tr ' /' '__'
}

is_true() {
    case "${1,,}" in
        1|true|yes|y|on) return 0 ;;
        *) return 1 ;;
    esac
}

count_saved() {
    local safe_word word_dir trial_dir count=0 full_tsv
    safe_word="$(safe_name "$1")"
    word_dir="$DATASET_ROOT/$safe_word"
    if [ ! -d "$word_dir" ]; then
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
    done < <(find "$word_dir" -mindepth 1 -maxdepth 1 -type d -name 'trial_*' 2>/dev/null)
    printf '%s\n' "$count"
}

catalog_duration() {
    awk -F '\t' -v word="$1" '$1 == word { sub(/\r$/, "", $2); print $2; exit }' "$CATALOG_FILE"
}

catalog_count() {
    awk -F '\t' 'NF >= 2 && $1 != "" { count++ } END { print count + 0 }' "$CATALOG_FILE"
}

next_trial_number() {
    local word_dir="$1"
    find "$word_dir" -mindepth 1 -maxdepth 1 -type d -name 'trial_*' -printf '%f\n' 2>/dev/null |
        awk -F_ '$2 ~ /^[0-9]+$/ { value=$2+0; if (value>max) max=value } END { printf "%03d", max+1 }'
}

pause_menu() {
    if [ -t 0 ]; then
        printf '\n계속하려면 Enter를 누르세요...'
        read -r _ || true
    fi
}

resource_summary() {
    local memory disk cpu load cores
    memory="N/A"
    disk="N/A"
    cpu="N/A"

    if [ -r /proc/meminfo ]; then
        memory="$(awk '/MemAvailable:/ { printf "%.0f MB", $2 / 1024; exit }' /proc/meminfo)"
        [ -n "$memory" ] || memory="N/A"
    fi
    if command -v df >/dev/null 2>&1; then
        disk="$(df -Pm "$BASE_DIR" 2>/dev/null | awk 'NR==2 { printf "%s MB", $4 }')"
        [ -n "$disk" ] || disk="N/A"
    fi
    if [ -r /proc/loadavg ]; then
        load="$(awk '{print $1}' /proc/loadavg)"
        cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
        cpu="load $load / ${cores} cores"
    fi

    printf '  메모리 상태 : %s\n' "$memory"
    if [ "$disk" = "N/A" ]; then
        printf '  디스크 상태 : %s\n' "$disk"
    else
        printf '  디스크 상태 : %s free\n' "$disk"
    fi
    printf '  CPU 상태    : %s\n' "$cpu"
}

show_main_menu() {
    clear_screen
    printf '%s+--------------------------------------------------+%s\n' "$C_TITLE" "$C_RESET"
    printf '%s|                 Sync:Us Collector                |%s\n' "$C_TITLE" "$C_RESET"
    printf '%s|         Korean Sign Language Data Recorder       |%s\n' "$C_TITLE" "$C_RESET"
    printf '%s+--------------------------------------------------+%s\n' "$C_TITLE" "$C_RESET"
    resource_summary
    printf '%s----------------------------------------------------%s\n' "$C_TITLE" "$C_RESET"
    printf '  1. 동작 리스트 보기\n'
    printf '  2. 촬영 시작\n'
    printf '  3. 저장 현황 보기\n'
    printf '  4. 도움말\n'
    printf '  0. 종료\n'
    printf '%s----------------------------------------------------%s\n' "$C_TITLE" "$C_RESET"
}

show_catalog() {
    local number=0 word seconds saved
    clear_screen
    printf '%s[동작 리스트]%s\n\n' "$C_TITLE" "$C_RESET"
    while IFS=$'\t' read -r word seconds || [ -n "${word:-}" ]; do
        seconds="${seconds%$'\r'}"
        [ -n "$word" ] || continue
        number=$((number + 1))
        saved="$(count_saved "$word")"
        printf '%2d. %-16s (%s/%s) - %s초\n' "$number" "$word" "$saved" "$MAX_SAMPLES_PER_WORD" "$seconds"
    done < "$CATALOG_FILE"
    pause_menu
}

show_status() {
    local total target saved_total=0 completed=0 word seconds saved progress
    total="$(catalog_count)"
    target=$((total * MAX_SAMPLES_PER_WORD))

    while IFS=$'\t' read -r word seconds || [ -n "${word:-}" ]; do
        [ -n "$word" ] || continue
        saved="$(count_saved "$word")"
        saved_total=$((saved_total + saved))
        if [ "$saved" -ge "$MAX_SAMPLES_PER_WORD" ]; then
            completed=$((completed + 1))
        fi
    done < "$CATALOG_FILE"

    if [ "$target" -gt 0 ]; then
        progress="$(awk -v saved="$saved_total" -v target="$target" 'BEGIN { printf "%.1f", saved / target * 100 }')"
    else
        progress="0.0"
    fi

    clear_screen
    printf '%s[저장 현황]%s\n\n' "$C_TITLE" "$C_RESET"
    printf '총 동작 수       : %s\n' "$total"
    printf '동작별 목표 수   : %s\n' "$MAX_SAMPLES_PER_WORD"
    printf '전체 목표 수집량 : %s\n' "$target"
    printf '현재 저장 수집량 : %s\n' "$saved_total"
    printf '진행률           : %s%%\n' "$progress"
    printf '완료 동작 수     : %s\n' "$completed"
    printf '미완료 동작 수   : %s\n' "$((total - completed))"
    pause_menu
}

show_help() {
    clear_screen
    printf '%s[도움말]%s\n\n' "$C_TITLE" "$C_RESET"
    printf 'Sync:Us Collector는 한국 수어 학습용 영상과 랜드마크를 수집합니다.\n\n'
    printf '1. 동작 리스트: catalog의 동작, 저장 횟수, 권장 시간을 표시합니다.\n'
    printf '2. 촬영 시작: 동작과 촬영자를 입력하고 영상을 촬영합니다.\n'
    printf '3. 저장 현황: 전체 목표와 현재 진행률을 표시합니다.\n'
    printf '4. 도움말: 프로그램 사용 방법을 표시합니다.\n'
    printf '0. 프로그램을 종료합니다.\n\n'
    printf '저장 구조: data/dataset/{동작}/trial_XXX_{촬영자}_{시각}/\n'
    printf '동작별 최대 저장 횟수는 %s회입니다.\n' "$MAX_SAMPLES_PER_WORD"
    printf '촬영 시간은 catalog 권장값이 자동 적용되며 1~60초로 직접 지정할 수 있습니다.\n'
    printf '촬영 후 Y(저장), N(폐기), R(같은 조건으로 재촬영)을 선택합니다.\n\n'
    printf '전체 흐름과 메뉴는 Shell Script가 제어합니다.\n'
    printf 'Python은 영상 녹화와 MediaPipe 랜드마크 추출 helper로만 사용됩니다.\n'
    pause_menu
}

archive_input_videos() {
    local old_video
    shopt -s nullglob
    for old_video in "$INPUT_DIR"/*.mp4; do
        mv "$old_video" "$ARCHIVE_DIR/"
    done
    shopt -u nullglob
}

newest_file() {
    local root="$1" marker="$2"
    find "$root" -type f -newer "$marker" -printf '%T@\t%p\n' 2>/dev/null |
        sort -nr | awk -F '\t' 'NR==1 { sub(/^[^\t]*\t/, ""); print; exit }'
}

newest_dir() {
    local root="$1" marker="$2"
    find "$root" -mindepth 1 -maxdepth 1 -type d -newer "$marker" -printf '%T@\t%p\n' 2>/dev/null |
        sort -nr | awk -F '\t' 'NR==1 { sub(/^[^\t]*\t/, ""); print; exit }'
}

latest_tsv=""
latest_part_dir=""
latest_report=""
latest_log=""

organize_pipeline_results() {
    local trial_dir="$1" marker="$2"
    local full_dir parts_root report_dir log_dir part
    full_dir="$trial_dir/landmarks/full"
    parts_root="$trial_dir/landmarks/parts"
    report_dir="$trial_dir/report"
    log_dir="$trial_dir/logs"

    latest_tsv="$(newest_file "$BASE_DIR/data/landmarks/all" "$marker")"
    latest_part_dir="$(newest_dir "$BASE_DIR/data/landmarks/parts" "$marker")"
    latest_report="$(newest_file "$BASE_DIR/data/reports" "$marker")"
    latest_log="$(newest_file "$BASE_DIR/logs" "$marker")"

    if [ -z "$latest_tsv" ] || [ -z "$latest_part_dir" ] || [ -z "$latest_report" ] || [ -z "$latest_log" ]; then
        printf '%s[ERROR] 파이프라인 결과 파일을 찾지 못했습니다.%s\n' "$C_ERR" "$C_RESET"
        return 1
    fi

    mkdir -p "$full_dir" "$report_dir" "$log_dir" || return 1
    cp "$latest_tsv" "$full_dir/all_landmarks.tsv" || return 1
    for part in pose face left_hand right_hand; do
        mkdir -p "$parts_root/$part" || return 1
        cp "$latest_part_dir/$part.tsv" "$parts_root/$part/$part.tsv" || return 1
    done
    cp "$latest_report" "$report_dir/report.txt" || return 1
    cp "$latest_log" "$log_dir/pipeline.log" || return 1
}

cleanup_pipeline_results() {
    local pipeline_input="$1"

    case "$latest_tsv" in "$BASE_DIR/data/landmarks/all/"*) ;; *) return 1 ;; esac
    case "$latest_part_dir" in "$BASE_DIR/data/landmarks/parts/"*) ;; *) return 1 ;; esac
    case "$latest_report" in "$BASE_DIR/data/reports/"*) ;; *) return 1 ;; esac
    case "$latest_log" in "$BASE_DIR/logs/"*) ;; *) return 1 ;; esac
    case "$pipeline_input" in "$INPUT_DIR/"*) ;; *) return 1 ;; esac

    rm -f -- "$latest_tsv" "$latest_report" "$latest_log" "$pipeline_input" || return 1
    rm -rf -- "$latest_part_dir" || return 1
}

archive_failed_collect_log() {
    local collect_log="$1" trial_name="$2" failed_dir failed_log
    [ -f "$collect_log" ] || return 0
    failed_dir="$BASE_DIR/logs/failed"
    mkdir -p "$failed_dir" || return 1
    failed_log="$failed_dir/failed_collect_${trial_name}.log"
    cp "$collect_log" "$failed_log" || return 1
    printf '%s\n' "${failed_log#"$BASE_DIR"/}"
}

discard_failed_trial() {
    local trial_dir="$1" pipeline_input="$2" collect_log="$3" trial_name="$4"
    local failed_log=""
    failed_log="$(archive_failed_collect_log "$collect_log" "$trial_name" 2>/dev/null || true)"
    rm -f -- "$pipeline_input"
    rm -rf -- "$trial_dir"

    printf '\n%s랜드마크가 정상적으로 추출되지 않았습니다.%s\n' "$C_ERR" "$C_RESET"
    printf '영상에서 얼굴, 상체, 양손이 충분히 보이는지 확인한 뒤 다시 촬영해 주세요.\n'
    printf '해당 촬영본은 저장 횟수에 포함되지 않습니다.\n'
    if [ -n "$failed_log" ]; then
        printf '실패 로그 : %s\n' "$failed_log"
    fi
}

organized_result_is_valid() {
    local trial_dir="$1" full_tsv part
    full_tsv="$trial_dir/landmarks/full/all_landmarks.tsv"
    [ -f "$full_tsv" ] && [ "$(wc -l < "$full_tsv")" -gt 1 ] || return 1
    [ -f "$trial_dir/report/report.txt" ] || return 1
    for part in pose face left_hand right_hand; do
        [ -f "$trial_dir/landmarks/parts/$part/$part.tsv" ] || return 1
    done
}

saved_frame_count() {
    local log_file="$1" count
    count="$(awk '
        {
            lower = tolower($0)
        }
        /저장된[[:space:]]*프레임[[:space:]]*수/ || lower ~ /saved[[:space:]_-]*frames?/ || lower ~ /saved.*frame/ {
            line = $0
            while (match(line, /[0-9]+/)) {
                value = substr(line, RSTART, RLENGTH)
                line = substr(line, RSTART + RLENGTH)
            }
            if (value != "") { print value; exit }
        }
    ' "$log_file" 2>/dev/null)"
    printf '%s\n' "${count:-확인 불가}"
}

result_box_row() {
    local text="$1" chars bytes wide padding
    chars="$(printf '%s' "$text" | wc -m | awk '{print $1}')"
    bytes="$(printf '%s' "$text" | wc -c | awk '{print $1}')"
    wide=$((chars + (bytes - chars) / 2))
    padding=$((48 - wide))
    [ "$padding" -lt 0 ] && padding=0
    printf '| %s%*s |\n' "$text" "$padding" ''
}

show_recording_result() {
    local word="$1" user_id="$2" duration="$3" frames="$4"
    printf '\n%s+--------------------------------------------------+%s\n' "$C_TITLE" "$C_RESET"
    printf '%s|                  촬영 결과 확인                  |%s\n' "$C_TITLE" "$C_RESET"
    printf '%s+--------------------------------------------------+%s\n' "$C_TITLE" "$C_RESET"
    result_box_row "동작명       : $word"
    result_box_row "촬영자 ID    : $user_id"
    result_box_row "촬영 시간    : ${duration}초"
    result_box_row "저장 프레임  : $frames"
    result_box_row "임시 파일    : raw/.candidate_video.mp4"
    printf '+--------------------------------------------------+\n'
    printf '| %s[Y]%s 저장하기                                     |\n' "$C_OK" "$C_RESET"
    printf '| %s[N]%s 폐기하기                                     |\n' "$C_WARN" "$C_RESET"
    printf '| %s[R]%s 재촬영하기                                   |\n' "$C_TITLE" "$C_RESET"
    printf '+--------------------------------------------------+\n'
}

finalize_recording() {
    local word="$1" safe_word="$2" user_id="$3" safe_user="$4" recommended="$5" duration="$6" custom="$7"
    local trial_no date_tag trial_name trial_dir raw_dir candidate candidate_log pipeline_input marker collect_log
    local answer record_ok frames relative_candidate relative_video relative_trial
    local record_args

    date_tag="$(date +'%Y%m%d_%H%M%S')"
    mkdir -p "$DATASET_ROOT/$safe_word"
    trial_no="$(next_trial_number "$DATASET_ROOT/$safe_word")"
    trial_name="trial_${trial_no}_${safe_user}_${date_tag}"
    trial_dir="$DATASET_ROOT/$safe_word/$trial_name"
    raw_dir="$trial_dir/raw"
    candidate="$raw_dir/.candidate_video.mp4"
    candidate_log="$raw_dir/.candidate_record.log"
    mkdir -p "$raw_dir"

    while true; do
        rm -f "$candidate" "$candidate_log"
        printf '\n%s[촬영 준비]%s\n' "$C_TITLE" "$C_RESET"
        printf '동작명       : %s\n' "$word"
        printf '촬영자 ID    : %s\n' "$user_id"
        printf '촬영 시간    : %s초\n' "$duration"
        printf '대기 시간    : %s초\n\n' "$RECORD_COUNTDOWN_SECONDS"
        printf '카메라가 준비되면 자동으로 촬영이 시작됩니다.\n\n'

        record_ok=1
        record_args=(
            --output "$candidate" \
            --camera 0 \
            --duration "$duration" \
            --countdown "$RECORD_COUNTDOWN_SECONDS" \
            --warmup "$CAMERA_WARMUP_SECONDS"
        )
        if is_true "$PREVIEW_MIRROR_ENABLED"; then
            record_args+=(--mirror-preview)
        else
            record_args+=(--no-mirror-preview)
        fi
        if is_true "$VIDEO_MIRROR_ENABLED"; then
            record_args+=(--mirror-video)
        fi
        "$VENV_PYTHON" "$RECORD_PY" "${record_args[@]}" > "$candidate_log" 2>&1 || record_ok=0

        if [ "$record_ok" -ne 1 ] || [ ! -s "$candidate" ]; then
            printf '%s[ERROR] 촬영 영상이 생성되지 않았습니다.%s\n' "$C_ERR" "$C_RESET"
            rm -rf "$trial_dir"
            return 1
        fi

        frames="$(saved_frame_count "$candidate_log")"
        relative_candidate="${candidate#"$BASE_DIR"/}"
        printf '촬영이 종료되었습니다.\n'
        printf '저장된 프레임 수 : %s\n' "$frames"
        printf '임시 경로 : %s\n' "$relative_candidate"

        while true; do
            show_recording_result "$word" "$user_id" "$duration" "$frames"
            printf '선택 > '
            read -r answer || answer="N"
            case "${answer^^}" in
                Y)
                    mkdir -p "$trial_dir/logs"
                    mv "$candidate_log" "$trial_dir/logs/collection.log"
                    archive_input_videos
                    pipeline_input="$INPUT_DIR/${safe_word}_${safe_user}_${date_tag}.mp4"
                    cp "$candidate" "$pipeline_input"
                    marker="$trial_dir/.pipeline_started"
                    touch "$marker"
                    collect_log="$trial_dir/logs/collect_detail.log"
                    printf '\n%s[저장 처리]%s\n' "$C_TITLE" "$C_RESET"
                    printf '영상을 저장했습니다.\n'
                    printf '랜드마크 추출 및 결과 정리를 진행합니다...\n'
                    if ! printf '%s\n%s\n' "$word" "$user_id" | bash "$RUN_PIPELINE" > "$collect_log" 2>&1; then
                        rm -f "$marker"
                        discard_failed_trial "$trial_dir" "$pipeline_input" "$collect_log" "$trial_name"
                        return 1
                    fi
                    if ! organize_pipeline_results "$trial_dir" "$marker" >> "$collect_log" 2>&1; then
                        rm -f "$marker"
                        discard_failed_trial "$trial_dir" "$pipeline_input" "$collect_log" "$trial_name"
                        return 1
                    fi
                    if ! bash "$VALIDATE_RESULT" \
                        "$trial_dir/landmarks/full/all_landmarks.tsv" \
                        "$latest_part_dir" >> "$collect_log" 2>&1 ||
                        ! organized_result_is_valid "$trial_dir"; then
                        rm -f "$marker"
                        cleanup_pipeline_results "$pipeline_input" >> "$collect_log" 2>&1 || true
                        discard_failed_trial "$trial_dir" "$pipeline_input" "$collect_log" "$trial_name"
                        return 1
                    fi
                    rm -f "$marker"
                    cat > "$trial_dir/metadata.txt" <<META
sign_word=$word
user_id=$user_id
trial_number=$trial_no
created_at=$date_tag
recommended_record_seconds=$recommended
record_seconds=$duration
custom_duration=$custom
countdown_seconds=3
camera_warmup_seconds=$CAMERA_WARMUP_SECONDS
preview_mirrored=$PREVIEW_MIRROR_ENABLED
video_mirrored=$VIDEO_MIRROR_ENABLED
video_path=$raw_dir/video.mp4
META
                    mv "$candidate" "$raw_dir/video.mp4"
                    if ! cleanup_pipeline_results "$pipeline_input"; then
                        printf '\n%s[ERROR] 중간 작업 파일을 정리하지 못했습니다.%s\n' "$C_ERR" "$C_RESET"
                        printf '디버깅을 위해 남은 중간 산출물을 유지합니다.\n'
                        return 1
                    fi
                    relative_video="${raw_dir#"$BASE_DIR"/}/video.mp4"
                    relative_trial="${trial_dir#"$BASE_DIR"/}"
                    printf '중간 작업 파일을 정리했습니다.\n'
                    printf '최종 결과는 %s에 저장되었습니다.\n' "$relative_trial/"
                    printf '\n%s저장이 완료되었습니다.%s\n' "$C_OK" "$C_RESET"
                    printf '최종 영상 경로 : %s\n' "$relative_video"
                    printf '결과 폴더 : %s\n' "$relative_trial"
                    return 0
                    ;;
                N)
                    rm -rf "$trial_dir"
                    printf '\n%s저장하지 않았습니다.%s\n' "$C_WARN" "$C_RESET"
                    printf '임시 파일과 빈 trial 폴더를 정리했습니다.\n'
                    return 0
                    ;;
                R)
                    rm -f "$candidate" "$candidate_log"
                    printf '%s같은 조건으로 재촬영합니다.%s\n' "$C_WARN" "$C_RESET"
                    break
                    ;;
                *)
                    printf '%sY, N, R 중 하나를 입력하세요.%s\n' "$C_ERR" "$C_RESET"
                    ;;
            esac
        done
    done
}

start_recording() {
    local word user_id safe_word safe_user recommended duration custom saved

    clear_screen
    printf '%s[촬영 시작]%s\n\n' "$C_TITLE" "$C_RESET"
    while true; do
        printf '동작명: '
        read -r word || return
        if [ -z "$word" ]; then
            printf '%s동작명을 입력하세요.%s\n' "$C_ERR" "$C_RESET"
            continue
        fi
        recommended="$(catalog_duration "$word")"
        if [ -z "$recommended" ]; then
            printf '%s등록되지 않은 동작입니다.%s\n' "$C_ERR" "$C_RESET"
            continue
        fi
        break
    done

    while true; do
        printf '촬영자 ID: '
        read -r user_id || return
        if [ -n "$user_id" ]; then
            break
        fi
        printf '%s촬영자 ID를 입력하세요.%s\n' "$C_ERR" "$C_RESET"
    done

    while true; do
        printf '임의 촬영시간(Enter: 권장 %s초): ' "$recommended"
        read -r duration || return
        if [ -z "$duration" ]; then
            duration="$recommended"
            custom=false
            break
        fi
        if [[ "$duration" =~ ^[0-9]+$ ]] && [ "$duration" -ge 1 ] && [ "$duration" -le 60 ]; then
            custom=true
            break
        fi
        printf '%s1초 이상 60초 이하의 정수를 입력하세요.%s\n' "$C_ERR" "$C_RESET"
    done

    safe_word="$(safe_name "$word")"
    safe_user="$(safe_name "$user_id")"
    saved="$(count_saved "$word")"
    if [ "$saved" -ge "$MAX_SAMPLES_PER_WORD" ]; then
        printf '%s저장 횟수를 모두 채웠기에 추가 저장할 수 없습니다.%s\n' "$C_WARN" "$C_RESET"
        pause_menu
        return
    fi

    if [ ! -x "$VENV_PYTHON" ] || [ ! -f "$RECORD_PY" ] ||
        [ ! -f "$RUN_PIPELINE" ] || [ ! -f "$VALIDATE_RESULT" ]; then
        printf '%s[ERROR] 녹화 또는 파이프라인 실행 파일을 확인하세요.%s\n' "$C_ERR" "$C_RESET"
        pause_menu
        return
    fi

    if [ -f "$CHECK_RESOURCES" ] && ! bash "$CHECK_RESOURCES"; then
        printf '%s[ERROR] 시스템 자원 점검을 통과하지 못했습니다.%s\n' "$C_ERR" "$C_RESET"
        pause_menu
        return
    fi

    finalize_recording "$word" "$safe_word" "$user_id" "$safe_user" "$recommended" "$duration" "$custom" || true
    pause_menu
}

main() {
    local choice
    while true; do
        show_main_menu
        printf '메뉴 선택: '
        if ! read -r choice; then
            printf '\n프로그램을 종료합니다.\n'
            break
        fi
        case "$choice" in
            1) show_catalog ;;
            2) start_recording ;;
            3) show_status ;;
            4) show_help ;;
            0)
                printf '프로그램을 종료합니다.\n'
                break
                ;;
            *)
                printf '%s잘못된 메뉴 입력입니다.%s\n' "$C_ERR" "$C_RESET"
                pause_menu
                ;;
        esac
    done
}

main "$@"
