#!/usr/bin/env python3
"""Run DTW feedback for one query TSV against one target label's references.

This wrapper keeps the DTW owner's TSV loading, normalization, and DTW distance
algorithm shape, but connects it to this collector's dataset layout:

    data/dataset/{target_label}/trial_*/landmarks/full/all_landmarks.tsv

MVP uses pose, left_hand, and right_hand only. Face landmarks are ignored.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


PART_NAMES = ("right_hand", "left_hand", "pose")
DEFAULT_PART_WEIGHTS = {
    "right_hand": 0.35,
    "left_hand": 0.35,
    "pose": 0.2,
}

LANDMARK_COUNTS = {
    "right_hand": 21,
    "left_hand": 21,
    "pose": 33,
}

LEFT_SHOULDER_INDEX = 11
RIGHT_SHOULDER_INDEX = 12
MIN_SHOULDER_WIDTH = 1e-6
VISIBILITY_THRESHOLD = 0.5

FRAME_COLUMN_ALIASES = ("frame_index", "frame", "frame_id", "frame_number")
TIMESTAMP_COLUMN_ALIASES = ("timestamp", "time", "t")
PART_COLUMN_ALIASES = ("part", "body_part", "landmark_part")
LANDMARK_INDEX_COLUMN_ALIASES = ("landmark_index", "landmark_id", "index", "id")

KOREAN_PART_NAMES = {
    "right_hand": "오른손",
    "left_hand": "왼손",
    "pose": "몸/자세",
}

Point3D = tuple[float, float, float]


class ShoulderReference:
    """Reusable shoulder reference for frame normalization."""

    def __init__(
        self,
        left: Point3D | None,
        right: Point3D | None,
        vector: Point3D | None,
        center: Point3D,
        width: float,
    ) -> None:
        self.left = left
        self.right = right
        self.vector = vector
        self.center = center
        self.width = width


def load_tsv_as_landmark_data(path: str | Path) -> dict[str, list[dict[str, Any]]]:
    """Load TSV landmarks into the standard ``{'frames': [...]}`` shape."""
    with Path(path).open("r", encoding="utf-8-sig", newline="") as file:
        rows = list(csv.DictReader(file, delimiter="\t"))

    if not rows:
        return {"frames": []}

    if _is_long_landmark_tsv(rows[0]):
        frames = _long_rows_to_frames(rows)
    else:
        frames = _wide_rows_to_frames(rows)

    return {"frames": frames}


def normalize_tsv_file(path: str | Path) -> dict[str, list[list[float]]]:
    """Convert a TSV file into normalized per-part sequences."""
    return normalize_landmark_data(load_tsv_as_landmark_data(path))


def normalize_landmark_data(data: Any) -> dict[str, list[list[float]]]:
    """Convert frame-based landmark data into normalized per-part sequences."""
    frames = extract_frames(data)
    return normalize_frames(frames)


def extract_frames(data: Any) -> list[dict[str, Any]]:
    """Return frame dictionaries from supported landmark data."""
    if isinstance(data, list):
        return [frame for frame in data if isinstance(frame, dict)]

    if not isinstance(data, dict):
        return []

    frames = data.get("frames")
    if isinstance(frames, list):
        return [frame for frame in frames if isinstance(frame, dict)]

    landmarks = data.get("landmarks")
    if isinstance(landmarks, list):
        return [frame for frame in landmarks if isinstance(frame, dict)]

    return []


def normalize_frames(frames: list[dict[str, Any]]) -> dict[str, list[list[float]]]:
    """Create body-part vector sequences from frames."""
    sequences: dict[str, list[list[float]]] = {part: [] for part in PART_NAMES}
    last_valid_reference = _find_initial_shoulder_reference(frames)

    for frame in frames:
        pose_landmarks = _get_part_landmarks(frame, "pose")
        shoulder_reference = _get_shoulder_reference(
            pose_landmarks,
            last_valid_reference,
        )
        if _has_complete_shoulders(shoulder_reference):
            last_valid_reference = shoulder_reference

        for part in PART_NAMES:
            landmarks = _get_part_landmarks(frame, part)
            sequences[part].append(
                flatten_landmarks(
                    landmarks=landmarks,
                    part=part,
                    shoulder_center=shoulder_reference.center,
                    shoulder_width=shoulder_reference.width,
                )
            )

    return sequences


def flatten_landmarks(
    landmarks: Any,
    part: str,
    shoulder_center: Point3D,
    shoulder_width: float,
) -> list[float]:
    """Flatten one frame of landmarks into a normalized numeric vector."""
    normalized_landmarks = _coerce_landmark_list(landmarks, LANDMARK_COUNTS[part])

    vector: list[float] = []
    for landmark in normalized_landmarks:
        if landmark is None:
            vector.extend([0.0, 0.0, 0.0])
            continue

        x = (_to_float(landmark.get("x")) - shoulder_center[0]) / shoulder_width
        y = (_to_float(landmark.get("y")) - shoulder_center[1]) / shoulder_width
        z = (_to_float(landmark.get("z")) - shoulder_center[2]) / shoulder_width
        vector.extend([x, y, z])

    return vector


def compare_landmark_sequences(
    reference_sequences: dict[str, list[list[float]]],
    user_sequences: dict[str, list[list[float]]],
) -> dict[str, Any]:
    """Compare normalized landmark sequences and return MVP part distances."""
    part_results: dict[str, dict[str, Any]] = {}

    for part in PART_NAMES:
        reference_part = reference_sequences.get(part, [])
        user_part = user_sequences.get(part, [])
        distance = dtw_distance(reference_part, user_part)
        part_results[part] = {
            "dtw_distance": distance,
            "reference_frame_count": len(reference_part),
            "user_frame_count": len(user_part),
        }

    total_distance = calculate_total_distance(part_results)
    main_feedback_part = _find_largest_distance_part(part_results)

    return {
        "total_distance": total_distance,
        "main_feedback_part": main_feedback_part,
        "part_results": part_results,
    }


def calculate_total_distance(part_results: dict[str, dict[str, Any]]) -> float:
    """Calculate a weighted MVP distance from per-part DTW distances."""
    weighted_total = 0.0
    used_weight_total = 0.0

    for part, weight in DEFAULT_PART_WEIGHTS.items():
        distance = float(part_results.get(part, {}).get("dtw_distance", math.inf))
        if not math.isfinite(distance):
            return math.inf
        weighted_total += distance * weight
        used_weight_total += weight

    if used_weight_total <= 0.0:
        return math.inf

    return weighted_total / used_weight_total


def compare_tsv_files(reference_path: str | Path, user_path: str | Path) -> dict[str, Any]:
    """Compare one reference TSV with one user TSV."""
    reference_sequences = normalize_tsv_file(reference_path)
    user_sequences = normalize_tsv_file(user_path)
    return compare_landmark_sequences(reference_sequences, user_sequences)


def dtw_distance(sequence_a: list[list[float]], sequence_b: list[list[float]]) -> float:
    """Calculate normalized DTW distance for two vector time series."""
    if not sequence_a and not sequence_b:
        return 0.0

    if not sequence_a or not sequence_b:
        return float("inf")

    row_count = len(sequence_a)
    column_count = len(sequence_b)
    previous_row = [float("inf")] * (column_count + 1)
    previous_row[0] = 0.0

    for row_index in range(1, row_count + 1):
        current_row = [float("inf")] * (column_count + 1)
        for column_index in range(1, column_count + 1):
            cost = euclidean_distance(
                sequence_a[row_index - 1],
                sequence_b[column_index - 1],
            )
            current_row[column_index] = cost + min(
                previous_row[column_index],
                current_row[column_index - 1],
                previous_row[column_index - 1],
            )
        previous_row = current_row

    path_length_estimate = row_count + column_count
    return previous_row[column_count] / path_length_estimate


def euclidean_distance(vector_a: list[float], vector_b: list[float]) -> float:
    """Return Euclidean distance between two same-length numeric vectors."""
    max_length = max(len(vector_a), len(vector_b))
    total = 0.0

    for index in range(max_length):
        value_a = vector_a[index] if index < len(vector_a) else 0.0
        value_b = vector_b[index] if index < len(vector_b) else 0.0
        diff = value_a - value_b
        total += diff * diff

    return math.sqrt(total)


def find_reference_tsvs(
    reference_root: str | Path,
    target_label: str,
    query_path: str | Path | None = None,
) -> list[Path]:
    """Find target-label reference all_landmarks.tsv files."""
    target_dir = Path(reference_root) / target_label
    if not target_dir.is_dir():
        raise FileNotFoundError(f"target-label 폴더가 없습니다: {target_dir}")

    query_resolved = Path(query_path).resolve() if query_path is not None else None
    all_reference_paths = sorted(
        path
        for path in target_dir.glob("trial_*/landmarks/full/all_landmarks.tsv")
        if path.is_file()
    )
    if not all_reference_paths:
        raise FileNotFoundError(
            f"reference TSV가 없습니다: {target_dir}/trial_*/landmarks/full/all_landmarks.tsv"
        )

    is_leave_one_out = (
        query_resolved is not None
        and any(path.resolve() == query_resolved for path in all_reference_paths)
    )
    reference_paths = [
        path
        for path in all_reference_paths
        if query_resolved is None or path.resolve() != query_resolved
    ]

    if is_leave_one_out:
        if not reference_paths:
            raise FileNotFoundError(
                f"leave-one-out 비교에 사용할 reference TSV가 없습니다: {target_dir}"
            )
        print(
            "query가 reference 폴더 내부에 있어 leave-one-out 테스트로 실행합니다. "
            f"비교 reference 수: {len(reference_paths)}"
        )
        return reference_paths

    if len(reference_paths) < 5:
        raise ValueError(
            f"reference TSV는 5개가 필요하지만 {len(reference_paths)}개만 찾았습니다: {target_dir}"
        )

    return reference_paths[:5]


def build_feedback_message(part: str | None) -> str:
    """Build the MVP feedback message from the largest-distance part."""
    if part == "right_hand":
        return "오른손 움직임이 reference와 가장 차이가 큽니다. 오른손의 위치와 이동 경로를 확인해보세요."
    if part == "left_hand":
        return "왼손 움직임이 reference와 가장 차이가 큽니다. 왼손의 위치와 이동 경로를 확인해보세요."
    if part == "pose":
        return "몸과 자세가 reference와 가장 차이가 큽니다. 어깨 위치와 전체 자세를 확인해보세요."
    return "reference와 차이가 큰 부위를 확인해보세요."


def build_output(
    target_label: str,
    best_reference: Path,
    comparison: dict[str, Any],
) -> dict[str, Any]:
    """Create the requested JSON output shape."""
    part_distances = {
        part: _json_number(comparison["part_results"][part]["dtw_distance"])
        for part in PART_NAMES
    }
    main_feedback_part = comparison["main_feedback_part"]

    return {
        "target_label": target_label,
        "best_reference": str(best_reference),
        "total_distance": _json_number(comparison["total_distance"]),
        "part_distances": part_distances,
        "main_feedback_part": main_feedback_part,
        "feedback_message": build_feedback_message(main_feedback_part),
    }


def print_result(result: dict[str, Any]) -> None:
    """Print DTW result and feedback to the terminal."""
    print(f"target_label: {result['target_label']}")
    print(f"best_reference: {result['best_reference']}")
    print(f"total_distance: {result['total_distance']}")
    print("part_distances:")
    for part in PART_NAMES:
        korean_name = KOREAN_PART_NAMES.get(part, part)
        print(f"- {part} ({korean_name}): {result['part_distances'][part]}")
    print(f"main_feedback_part: {result['main_feedback_part']}")
    print(f"feedback_message: {result['feedback_message']}")


def run_feedback(
    query_path: str | Path,
    reference_root: str | Path,
    target_label: str,
) -> dict[str, Any]:
    """Run target-label-only DTW comparison and select the nearest reference."""
    query = Path(query_path)
    if not query.is_file():
        raise FileNotFoundError(f"query TSV가 없습니다: {query}")

    reference_paths = find_reference_tsvs(reference_root, target_label, query)
    user_sequences = normalize_tsv_file(query)

    comparisons: list[tuple[Path, dict[str, Any]]] = []
    for reference_path in reference_paths:
        reference_sequences = normalize_tsv_file(reference_path)
        comparison = compare_landmark_sequences(reference_sequences, user_sequences)
        comparisons.append((reference_path, comparison))

    best_reference, best_comparison = min(
        comparisons,
        key=lambda item: item[1]["total_distance"],
    )
    return build_output(target_label, best_reference, best_comparison)


def save_json(result: dict[str, Any], output_path: str | Path) -> None:
    """Save feedback result as UTF-8 JSON."""
    path = Path(output_path)
    if path.parent:
        path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, indent=2)
        file.write("\n")


def _is_long_landmark_tsv(row: dict[str, Any]) -> bool:
    """Return whether a row appears to represent a single landmark."""
    keys = {_normalize_key(key) for key in row}
    return (
        {"x", "y"}.issubset(keys)
        and any(key in keys for key in PART_COLUMN_ALIASES)
        and any(key in keys for key in LANDMARK_INDEX_COLUMN_ALIASES)
    )


def _long_rows_to_frames(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convert one-landmark-per-row TSV data into frame dictionaries."""
    frames_by_key: dict[str, dict[str, Any]] = {}
    frame_order: list[str] = []

    for row_number, row in enumerate(rows):
        frame_key = str(_row_value(row, FRAME_COLUMN_ALIASES, row_number))
        if frame_key not in frames_by_key:
            frames_by_key[frame_key] = {
                "frame_index": _to_int(frame_key, len(frame_order)),
                "timestamp": _to_float(
                    _row_value(row, TIMESTAMP_COLUMN_ALIASES, len(frame_order))
                ),
            }
            frame_order.append(frame_key)

        part = _normalize_part_name(_row_value(row, PART_COLUMN_ALIASES, ""))
        if part is None:
            continue

        landmark_index = _to_int(
            _row_value(row, LANDMARK_INDEX_COLUMN_ALIASES, -1),
            -1,
        )
        if landmark_index < 0 or landmark_index >= LANDMARK_COUNTS[part]:
            continue

        frame = frames_by_key[frame_key]
        landmarks = frame.setdefault(part, [None] * LANDMARK_COUNTS[part])
        landmarks[landmark_index] = _landmark_from_row(
            row,
            include_visibility=(part == "pose"),
        )

    return [frames_by_key[key] for key in frame_order]


def _wide_rows_to_frames(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convert one-frame-per-row TSV data into frame dictionaries."""
    column_map = _build_wide_column_map(rows[0])
    frames: list[dict[str, Any]] = []

    for row_number, row in enumerate(rows):
        frame = {
            "frame_index": _to_int(
                _row_value(row, FRAME_COLUMN_ALIASES, row_number),
                row_number,
            ),
            "timestamp": _to_float(
                _row_value(row, TIMESTAMP_COLUMN_ALIASES, row_number)
            ),
        }

        for part, landmark_index, axis, column_name in column_map:
            landmarks = frame.setdefault(part, [None] * LANDMARK_COUNTS[part])
            landmark = landmarks[landmark_index]
            if landmark is None:
                landmark = {}
                landmarks[landmark_index] = landmark
            landmark[axis] = _to_float(row.get(column_name))

        frames.append(frame)

    return frames


def _build_wide_column_map(row: dict[str, Any]) -> list[tuple[str, int, str, str]]:
    """Map columns such as ``right_hand_0_x`` to landmark coordinates."""
    column_map: list[tuple[str, int, str, str]] = []
    pattern = re.compile(r"(.+?)[_.\[](\d+)[_\].]+(x|y|z|visibility)$")

    for column_name in row:
        match = pattern.match(_normalize_key(column_name))
        if not match:
            continue

        part = _normalize_part_name(match.group(1))
        if part is None:
            continue

        landmark_index = _to_int(match.group(2), -1)
        if 0 <= landmark_index < LANDMARK_COUNTS[part]:
            column_map.append((part, landmark_index, match.group(3), column_name))

    return column_map


def _landmark_from_row(row: dict[str, Any], include_visibility: bool) -> dict[str, float]:
    """Create a landmark dictionary from long-format TSV coordinates."""
    landmark = {
        "x": _to_float(_row_value(row, ("x",), 0.0)),
        "y": _to_float(_row_value(row, ("y",), 0.0)),
        "z": _to_float(_row_value(row, ("z",), 0.0)),
    }
    if include_visibility:
        landmark["visibility"] = _to_float(_row_value(row, ("visibility",), 1.0))

    return landmark


def _get_part_landmarks(frame: dict[str, Any], part: str) -> Any:
    """Read part landmarks using common MediaPipe export key names."""
    if part in frame:
        return frame[part]

    key = f"{part}_landmarks"
    if key in frame:
        return frame[key]

    return None


def _find_initial_shoulder_reference(frames: list[dict[str, Any]]) -> ShoulderReference:
    """Find the first fully reliable shoulder reference in the whole sequence."""
    fallback = ShoulderReference(
        left=None,
        right=None,
        vector=None,
        center=(0.0, 0.0, 0.0),
        width=1.0,
    )

    for frame in frames:
        reference = _get_shoulder_reference(_get_part_landmarks(frame, "pose"), fallback)
        if _has_complete_shoulders(reference):
            return reference

    return fallback


def _get_shoulder_reference(
    landmarks: Any,
    last_valid_reference: ShoulderReference | None = None,
) -> ShoulderReference:
    """Calculate shoulder center and width using shoulder visibility fallbacks."""
    fallback = last_valid_reference or ShoulderReference(
        left=None,
        right=None,
        vector=None,
        center=(0.0, 0.0, 0.0),
        width=1.0,
    )
    pose_landmarks = _coerce_landmark_list(landmarks, LANDMARK_COUNTS["pose"])
    left = pose_landmarks[LEFT_SHOULDER_INDEX]
    right = pose_landmarks[RIGHT_SHOULDER_INDEX]
    left_reliable = _is_reliable_shoulder(left)
    right_reliable = _is_reliable_shoulder(right)

    if left_reliable and right_reliable:
        left_point = _landmark_point(left)
        right_point = _landmark_point(right)
        center, width = _calculate_center_and_width(left_point, right_point)
        return ShoulderReference(
            left=left_point,
            right=right_point,
            vector=_subtract_points(right_point, left_point),
            center=center,
            width=width,
        )

    if left_reliable and fallback.vector is not None:
        left_point = _landmark_point(left)
        right_point = _add_points(left_point, fallback.vector)
        center, width = _calculate_center_and_width(left_point, right_point)
        return ShoulderReference(
            left=left_point,
            right=right_point,
            vector=None,
            center=center,
            width=width,
        )

    if right_reliable and fallback.vector is not None:
        right_point = _landmark_point(right)
        left_point = _subtract_points(right_point, fallback.vector)
        center, width = _calculate_center_and_width(left_point, right_point)
        return ShoulderReference(
            left=left_point,
            right=right_point,
            vector=None,
            center=center,
            width=width,
        )

    return ShoulderReference(
        left=fallback.left,
        right=fallback.right,
        vector=None,
        center=fallback.center,
        width=fallback.width,
    )


def _has_complete_shoulders(reference: ShoulderReference) -> bool:
    """Return whether a reference came from two reliable current shoulders."""
    return (
        reference.left is not None
        and reference.right is not None
        and reference.vector is not None
    )


def _is_reliable_shoulder(landmark: dict[str, Any] | None) -> bool:
    """Return whether a shoulder landmark is visible enough for normalization."""
    if landmark is None:
        return False

    return _to_float(landmark.get("visibility")) > VISIBILITY_THRESHOLD


def _coerce_landmark_list(
    landmarks: Any,
    expected_count: int,
) -> list[dict[str, Any] | None]:
    """Return a fixed-length landmark list, preserving missing values as None."""
    if not isinstance(landmarks, list):
        return [None] * expected_count

    coerced: list[dict[str, Any] | None] = []
    for landmark in landmarks[:expected_count]:
        if isinstance(landmark, dict):
            coerced.append(landmark)
        else:
            coerced.append(None)

    if len(coerced) < expected_count:
        coerced.extend([None] * (expected_count - len(coerced)))

    return coerced


def _landmark_point(landmark: dict[str, Any]) -> Point3D:
    """Return the x, y, z coordinates for a landmark."""
    return (
        _to_float(landmark.get("x")),
        _to_float(landmark.get("y")),
        _to_float(landmark.get("z")),
    )


def _calculate_center_and_width(
    left_point: Point3D,
    right_point: Point3D,
) -> tuple[Point3D, float]:
    """Calculate shoulder center and width from left and right shoulder points."""
    width = math.dist(left_point, right_point)
    if width < MIN_SHOULDER_WIDTH:
        width = 1.0

    center = (
        (left_point[0] + right_point[0]) / 2.0,
        (left_point[1] + right_point[1]) / 2.0,
        (left_point[2] + right_point[2]) / 2.0,
    )
    return center, width


def _add_points(point_a: Point3D, point_b: Point3D) -> Point3D:
    """Add two 3D points component-wise."""
    return (
        point_a[0] + point_b[0],
        point_a[1] + point_b[1],
        point_a[2] + point_b[2],
    )


def _subtract_points(point_a: Point3D, point_b: Point3D) -> Point3D:
    """Subtract one 3D point from another component-wise."""
    return (
        point_a[0] - point_b[0],
        point_a[1] - point_b[1],
        point_a[2] - point_b[2],
    )


def _find_largest_distance_part(part_results: dict[str, dict[str, Any]]) -> str | None:
    """Return the part with the largest finite DTW distance."""
    finite_parts = [
        part
        for part in PART_NAMES
        if math.isfinite(float(part_results.get(part, {}).get("dtw_distance", math.inf)))
    ]
    if not finite_parts:
        return None

    return max(finite_parts, key=lambda part: part_results[part]["dtw_distance"])


def _row_value(row: dict[str, Any], names: tuple[str, ...], default: Any) -> Any:
    """Return a row value by normalized column aliases."""
    wanted = set(names)
    for key, value in row.items():
        if _normalize_key(key) in wanted:
            return value

    return default


def _normalize_key(value: Any) -> str:
    """Normalize TSV column labels."""
    return str(value).strip().lower().replace(" ", "_").replace("-", "_")


def _normalize_part_name(value: Any) -> str | None:
    """Map common TSV part labels to the internal part names."""
    normalized = _normalize_key(value).replace("__", "_")
    aliases = {
        "right_hand": "right_hand",
        "righthand": "right_hand",
        "right": "right_hand",
        "right_hand_landmarks": "right_hand",
        "left_hand": "left_hand",
        "lefthand": "left_hand",
        "left": "left_hand",
        "left_hand_landmarks": "left_hand",
        "pose": "pose",
        "pose_landmarks": "pose",
    }
    return aliases.get(normalized)


def _to_float(value: Any) -> float:
    """Convert values to finite floats."""
    if isinstance(value, bool):
        return 0.0

    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0

    if not math.isfinite(number):
        return 0.0

    return number


def _to_int(value: Any, default: int) -> int:
    """Convert values to ints."""
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _json_number(value: Any) -> float | str:
    """Return JSON-safe finite floats, preserving non-finite values as strings."""
    number = float(value)
    if math.isfinite(number):
        return round(number, 6)
    return "Infinity"


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="Compare one query all_landmarks.tsv with target-label references."
    )
    parser.add_argument("--query", required=True, help="Query all_landmarks.tsv path.")
    parser.add_argument(
        "--reference-root",
        required=True,
        help="Dataset root path, for example data/dataset.",
    )
    parser.add_argument(
        "--target-label",
        required=True,
        help="Target sign label. Only this folder is used for references.",
    )
    parser.add_argument(
        "--output-json",
        help="Optional JSON output path. Example: output/dtw_feedback.json",
    )
    return parser.parse_args()


def main() -> int:
    """Run target-label DTW feedback from the command line."""
    args = parse_args()

    try:
        result = run_feedback(args.query, args.reference_root, args.target_label)
        print_result(result)
        if args.output_json:
            save_json(result, args.output_json)
            print(f"json_saved: {args.output_json}")
        return 0
    except (FileNotFoundError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
