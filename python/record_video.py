#!/usr/bin/env python3

import cv2
import argparse
import os
import time
import sys


def draw_center_text(frame, text, y_offset=0, scale=1.1, color=(0, 255, 255)):
    height, width = frame.shape[:2]
    font = cv2.FONT_HERSHEY_SIMPLEX
    thickness = 3

    text_size, _ = cv2.getTextSize(text, font, scale, thickness)
    text_x = (width - text_size[0]) // 2
    text_y = (height // 2) + y_offset

    cv2.putText(
        frame,
        text,
        (text_x, text_y),
        font,
        scale,
        color,
        thickness,
        cv2.LINE_AA
    )


def show_frame(window_name, frame, display_scale=2):
    """
    저장되는 영상 해상도는 유지하되,
    사용자에게 보이는 카메라 화면만 확대해서 표시한다.
    """
    if display_scale <= 1:
        cv2.imshow(window_name, frame)
        return

    height, width = frame.shape[:2]
    display_frame = cv2.resize(
        frame,
        (width * display_scale, height * display_scale),
        interpolation=cv2.INTER_LINEAR
    )
    cv2.imshow(window_name, display_frame)


def make_display_frame(frame, mirror_preview):
    if mirror_preview:
        return cv2.flip(frame, 1)
    return frame.copy()


def show_preview(cap, width, height, warmup, mirror_preview=True):
    print(f"[INFO] 카메라 화면 준비 중입니다. {warmup}초 후 카운트다운이 시작됩니다.")

    start_time = time.time()

    while True:
        ret, frame = cap.read()

        if not ret:
            print("[ERROR] 카메라 프레임을 읽지 못했습니다.")
            sys.exit(1)

        frame = cv2.resize(frame, (width, height))
        display_frame = make_display_frame(frame, mirror_preview)

        elapsed = time.time() - start_time
        remaining = max(0, warmup - int(elapsed))

        draw_center_text(display_frame, "Camera Ready", y_offset=-45, scale=1.1, color=(0, 255, 255))
        draw_center_text(display_frame, f"Countdown starts in {remaining}", y_offset=25, scale=0.9, color=(255, 255, 255))

        cv2.putText(
            display_frame,
            "Recording has NOT started",
            (20, 40),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 255, 255),
            2,
            cv2.LINE_AA
        )

        show_frame("KSL Recorder", display_frame, display_scale=2)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            print("[INFO] q 입력으로 녹화를 취소했습니다.")
            sys.exit(0)

        if elapsed >= warmup:
            break


def run_countdown(cap, width, height, countdown, mirror_preview=True):
    print(f"[INFO] 녹화 시작 전 {countdown}초 카운트다운을 시작합니다.")

    start_time = time.time()

    while True:
        ret, frame = cap.read()

        if not ret:
            print("[ERROR] 카메라 프레임을 읽지 못했습니다.")
            sys.exit(1)

        frame = cv2.resize(frame, (width, height))
        display_frame = make_display_frame(frame, mirror_preview)

        elapsed = time.time() - start_time
        remaining = countdown - int(elapsed)

        if remaining <= 0:
            break

        draw_center_text(display_frame, f"Recording starts in {remaining}", y_offset=-20, scale=1.1, color=(0, 255, 255))
        draw_center_text(display_frame, "Get ready!", y_offset=40, scale=1.0, color=(255, 255, 255))

        show_frame("KSL Recorder", display_frame, display_scale=2)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            print("[INFO] q 입력으로 녹화를 취소했습니다.")
            sys.exit(0)


def record_video(
    output_path,
    camera_index=0,
    duration=8,
    countdown=3,
    warmup=3,
    width=640,
    height=480,
    fps=20,
    mirror_preview=True,
    mirror_video=False,
):
    cap = cv2.VideoCapture(camera_index)

    if not cap.isOpened():
        print(f"[ERROR] 카메라를 열 수 없습니다. camera_index={camera_index}")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

    if not out.isOpened():
        print(f"[ERROR] VideoWriter를 열 수 없습니다: {output_path}")
        cap.release()
        sys.exit(1)

    cv2.namedWindow("KSL Recorder", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("KSL Recorder", 1280, 960)
    cv2.moveWindow("KSL Recorder", 100, 80)

    print(f"[INFO] 저장 경로: {output_path}")
    print(f"[INFO] 카메라 준비 시간: {warmup}초")
    print(f"[INFO] 녹화 전 카운트다운: {countdown}초")
    print(f"[INFO] 실제 녹화 시간: {duration}초")
    print(f"[INFO] preview_mirrored={str(mirror_preview).lower()}")
    print(f"[INFO] video_mirrored={str(mirror_video).lower()}")
    print("[GUIDE] q를 누르면 취소 또는 조기 종료됩니다.")

    # 1. 카메라 창을 먼저 띄우고 사용자가 화면을 인지할 시간을 준다.
    show_preview(cap, width, height, warmup, mirror_preview=mirror_preview)

    # 2. 녹화 시작 전 카운트다운을 표시한다.
    run_countdown(cap, width, height, countdown, mirror_preview=mirror_preview)

    # 3. 실제 녹화 시작
    print("[INFO] 지금부터 실제 녹화를 시작합니다.")

    start_time = time.time()
    frame_count = 0

    while True:
        ret, frame = cap.read()

        if not ret:
            print("[ERROR] 카메라 프레임을 읽지 못했습니다.")
            break

        frame = cv2.resize(frame, (width, height))

        elapsed = time.time() - start_time
        remaining = max(0, duration - int(elapsed))

        saved_frame = cv2.flip(frame, 1) if mirror_video else frame.copy()
        display_frame = make_display_frame(frame, mirror_preview)

        cv2.putText(
            saved_frame,
            f"REC  {remaining}s left",
            (20, 40),
            cv2.FONT_HERSHEY_SIMPLEX,
            1.0,
            (0, 0, 255),
            3,
            cv2.LINE_AA
        )

        cv2.putText(
            display_frame,
            f"REC  {remaining}s left",
            (20, 40),
            cv2.FONT_HERSHEY_SIMPLEX,
            1.0,
            (0, 0, 255),
            3,
            cv2.LINE_AA
        )

        out.write(saved_frame)
        frame_count += 1

        show_frame("KSL Recorder", display_frame, display_scale=2)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            print("[INFO] q 입력으로 녹화를 종료합니다.")
            break

        if elapsed >= duration:
            print("[INFO] 지정된 녹화 시간이 끝났습니다.")
            break

    cap.release()
    out.release()
    cv2.destroyAllWindows()

    print(f"[DONE] 녹화 완료: {output_path}")
    print(f"[INFO] 저장된 프레임 수: {frame_count}")


def main():
    parser = argparse.ArgumentParser(description="웹캠으로 mp4 영상을 녹화합니다.")
    parser.add_argument("--output", required=True, help="저장할 mp4 파일 경로")
    parser.add_argument("--camera", type=int, default=0, help="카메라 번호")
    parser.add_argument("--duration", type=int, default=8, help="녹화 시간, 초 단위")
    parser.add_argument("--countdown", type=int, default=3, help="녹화 시작 전 카운트다운 시간, 초 단위")
    parser.add_argument("--warmup", type=int, default=3, help="카메라 창 준비 시간, 초 단위")
    parser.add_argument("--width", type=int, default=640, help="영상 가로 크기")
    parser.add_argument("--height", type=int, default=480, help="영상 세로 크기")
    parser.add_argument("--fps", type=int, default=20, help="FPS")
    mirror_preview_group = parser.add_mutually_exclusive_group()
    mirror_preview_group.add_argument(
        "--mirror-preview",
        dest="mirror_preview",
        action="store_true",
        default=True,
        help="촬영 미리보기 화면을 좌우 반전합니다. 기본값입니다.",
    )
    mirror_preview_group.add_argument(
        "--no-mirror-preview",
        dest="mirror_preview",
        action="store_false",
        help="촬영 미리보기 화면을 원본 방향으로 표시합니다.",
    )
    parser.add_argument(
        "--mirror-video",
        action="store_true",
        default=False,
        help="저장 mp4도 좌우 반전합니다. 기본값은 원본 방향 저장입니다.",
    )

    args = parser.parse_args()

    record_video(
        output_path=args.output,
        camera_index=args.camera,
        duration=args.duration,
        countdown=args.countdown,
        warmup=args.warmup,
        width=args.width,
        height=args.height,
        fps=args.fps,
        mirror_preview=args.mirror_preview,
        mirror_video=args.mirror_video,
    )


if __name__ == "__main__":
    main()
