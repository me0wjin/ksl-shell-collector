#!/usr/bin/env python3

import argparse
import csv
import glob
import os
import sys
from datetime import datetime

import cv2
import mediapipe as mp


mp_holistic = mp.solutions.holistic


TSV_HEADER = [
    "video",
    "frame",
    "part",
    "landmark_id",
    "x",
    "y",
    "z",
    "visibility",
    "timestamp",
]


def write_pose_landmarks(writer, video_name, frame_index, timestamp, landmarks):
    """Write pose landmarks with x, y, z, and visibility."""
    if landmarks is None:
        return

    for landmark_id, lm in enumerate(landmarks.landmark):
        writer.writerow(
            [
                video_name,
                frame_index,
                "pose",
                landmark_id,
                lm.x,
                lm.y,
                lm.z,
                lm.visibility,
                timestamp,
            ]
        )


def write_landmarks(writer, video_name, frame_index, timestamp, part_name, landmarks):
    """Write face and hand landmarks with x, y, z. Visibility is left blank."""
    if landmarks is None:
        return

    for landmark_id, lm in enumerate(landmarks.landmark):
        writer.writerow(
            [
                video_name,
                frame_index,
                part_name,
                landmark_id,
                lm.x,
                lm.y,
                lm.z,
                "",
                timestamp,
            ]
        )


def process_video(input_path, output_path) -> bool:
    """
    Process one video and save all MediaPipe Holistic landmarks as a TSV file.

    Returns True when the TSV file is created successfully, otherwise False.
    Directory processing, part splitting, validation, and reporting are handled by
    shell scripts in this project.
    """
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        print(f"[ERROR] Cannot open video: {input_path}")
        return False

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    video_name = os.path.basename(input_path)
    frame_index = 0

    try:
        with open(output_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, delimiter="\t")
            writer.writerow(TSV_HEADER)

            with mp_holistic.Holistic(
                static_image_mode=False,
                model_complexity=1,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            ) as holistic:
                while cap.isOpened():
                    success, image = cap.read()
                    if not success:
                        break

                    timestamp_sec = round(cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0, 4)

                    image.flags.writeable = False
                    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                    results = holistic.process(image_rgb)

                    write_pose_landmarks(
                        writer,
                        video_name,
                        frame_index,
                        timestamp_sec,
                        results.pose_landmarks,
                    )
                    write_landmarks(
                        writer,
                        video_name,
                        frame_index,
                        timestamp_sec,
                        "face",
                        results.face_landmarks,
                    )
                    write_landmarks(
                        writer,
                        video_name,
                        frame_index,
                        timestamp_sec,
                        "left_hand",
                        results.left_hand_landmarks,
                    )
                    write_landmarks(
                        writer,
                        video_name,
                        frame_index,
                        timestamp_sec,
                        "right_hand",
                        results.right_hand_landmarks,
                    )

                    frame_index += 1
    except OSError as exc:
        print(f"[ERROR] Failed to save TSV: {output_path} ({exc})")
        return False
    finally:
        cap.release()

    if not os.path.isfile(output_path):
        print(f"[ERROR] Output TSV was not created: {output_path}")
        return False

    print(f"[PYTHON] MediaPipe landmark extraction complete: {output_path}")
    print(f"[PYTHON] Total processed frames: {frame_index}")
    print(f"[PYTHON] Processed at: {datetime.now()}")
    return True


def process_directory(input_dir, output_dir) -> bool:
    """
    Process every mp4 file in a directory and save one TSV file per video.

    This is an optional convenience mode. The main shell pipeline still calls
    process_video once per input video.
    """
    video_files = glob.glob(os.path.join(input_dir, "*.mp4"))
    if not video_files:
        print(f"[WARNING] No mp4 files found in: {input_dir}")
        return False

    os.makedirs(output_dir, exist_ok=True)
    print(f"[PYTHON] Found {len(video_files)} mp4 files.")

    all_success = True
    for idx, video_path in enumerate(video_files, 1):
        base_name = os.path.splitext(os.path.basename(video_path))[0]
        output_path = os.path.join(output_dir, f"{base_name}_all.tsv")
        print(f"[PYTHON] [{idx}/{len(video_files)}] Processing: {video_path}")

        if not process_video(video_path, output_path):
            all_success = False

    return all_success


def parse_args():
    parser = argparse.ArgumentParser(
        description="Extract MediaPipe Holistic landmarks from videos as TSV."
    )

    parser.add_argument("input_video", nargs="?", help="input mp4 file path")
    parser.add_argument("output_tsv", nargs="?", help="output TSV file path")
    parser.add_argument("--input", dest="input_file", help="input mp4 file path")
    parser.add_argument("--output", dest="output_file", help="output TSV file path")
    parser.add_argument("--input_dir", help="directory containing mp4 files")
    parser.add_argument("--output_dir", help="directory for output TSV files")

    return parser.parse_args()


def main():
    args = parse_args()

    input_video = args.input_file or args.input_video
    output_tsv = args.output_file or args.output_tsv

    if input_video and output_tsv:
        if not os.path.isfile(input_video):
            print(f"[ERROR] Input video file does not exist: {input_video}")
            sys.exit(1)

        success = process_video(input_video, output_tsv)
        sys.exit(0 if success else 1)

    if args.input_dir and args.output_dir:
        success = process_directory(args.input_dir, args.output_dir)
        sys.exit(0 if success else 1)

    print(
        "[ERROR] Usage: extract_landmarks_tsv.py <input_video> <output_tsv> "
        "or --input <input_video> --output <output_tsv> "
        "or --input_dir <input_dir> --output_dir <output_dir>"
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
