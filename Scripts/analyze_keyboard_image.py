#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Proposal:
    x: float
    y: float
    width: float
    height: float
    rotation: float
    confidence: float
    source: str

    def to_json(self, proposal_id: int) -> dict[str, Any]:
        return {
            "id": f"proposal-{proposal_id}",
            "x": round(self.x, 3),
            "y": round(self.y, 3),
            "width": round(self.width, 3),
            "height": round(self.height, 3),
            "rotation": round(self.rotation, 3),
            "confidence": round(self.confidence, 4),
            "source": self.source,
        }


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Analyze a keyboard photo into key proposals.")
    parser.add_argument("--image", required=True, help="Path to the source image")
    parser.add_argument("--output", required=True, help="Path to write the analysis JSON")
    parser.add_argument("--yolo-model", default="", help="Optional Ultralytics YOLO/OBB model path or model name")
    return parser


def rotated_rect_to_proposal(rect: tuple[tuple[float, float], tuple[float, float], float], confidence: float, source: str) -> Proposal:
    (center_x, center_y), (width, height), angle = rect
    if width < height:
        width, height = height, width
        angle += 90
    return Proposal(
        x=center_x - (width / 2),
        y=center_y - (height / 2),
        width=width,
        height=height,
        rotation=angle,
        confidence=confidence,
        source=source,
    )


def try_yolo(image_path: Path, model_name: str) -> list[Proposal]:
    if not model_name:
        return []

    try:
        from ultralytics import YOLO  # type: ignore
    except Exception:
        return []

    model = YOLO(model_name)
    results = model.predict(str(image_path), verbose=False)
    proposals: list[Proposal] = []
    for result in results:
        obb = getattr(result, "obb", None)
        if obb is None:
            continue
        xywhr = getattr(obb, "xywhr", None)
        conf = getattr(obb, "conf", None)
        if xywhr is None or conf is None:
            continue

        xywhr_np = xywhr.cpu().numpy()
        conf_np = conf.cpu().numpy()
        for row, score in zip(xywhr_np, conf_np):
            cx, cy, width, height, rotation_radians = row
            rotation = math.degrees(rotation_radians)
            proposals.append(
                Proposal(
                    x=float(cx - (width / 2)),
                    y=float(cy - (height / 2)),
                    width=float(width),
                    height=float(height),
                    rotation=float(rotation),
                    confidence=float(score),
                    source="yolo-obb",
                )
            )
    return dedupe_proposals(proposals)


def materialize_image_for_cv(image_path: Path) -> tuple[Path, callable[[], None]]:
    suffix = image_path.suffix.lower()
    if suffix not in {".heic", ".heif"}:
        return image_path, lambda: None

    temp_file = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    temp_file.close()
    temp_path = Path(temp_file.name)

    try:
        subprocess.run(
            ["sips", "-s", "format", "png", str(image_path), "--out", str(temp_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    except Exception as exc:
        try:
            temp_path.unlink(missing_ok=True)
        except Exception:
            pass
        raise RuntimeError(f"Could not convert image for analysis: {image_path}") from exc

    def cleanup() -> None:
        try:
            temp_path.unlink(missing_ok=True)
        except Exception:
            pass

    return temp_path, cleanup


def fallback_opencv(image_path: Path) -> tuple[list[Proposal], tuple[int, int]]:
    try:
        import cv2  # type: ignore
    except Exception as exc:
        raise RuntimeError("OpenCV fallback unavailable. Install opencv-python.") from exc

    materialized_path, cleanup = materialize_image_for_cv(image_path)
    try:
        image = cv2.imread(str(materialized_path), cv2.IMREAD_COLOR)
        if image is None:
            raise RuntimeError(f"Could not load image: {image_path}")

        height, width = image.shape[:2]
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        adaptive = cv2.adaptiveThreshold(
            blurred,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY_INV,
            41,
            8,
        )
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        cleaned = cv2.morphologyEx(adaptive, cv2.MORPH_OPEN, kernel, iterations=1)

        contours, _ = cv2.findContours(cleaned, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        proposals: list[Proposal] = []
        min_area = max(250.0, (width * height) * 0.00003)
        max_area = (width * height) * 0.03

        for contour in contours:
            area = cv2.contourArea(contour)
            if area < min_area or area > max_area:
                continue

            perimeter = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.04 * perimeter, True)
            if len(approx) < 4:
                continue

            rect = cv2.minAreaRect(contour)
            (_, _), (rect_w, rect_h), _ = rect
            if rect_w < 8 or rect_h < 8:
                continue

            ratio = max(rect_w, rect_h) / max(min(rect_w, rect_h), 1)
            if ratio > 4.5:
                continue

            fill_ratio = float(area / max(rect_w * rect_h, 1))
            if fill_ratio < 0.45:
                continue

            proposals.append(rotated_rect_to_proposal(rect, confidence=min(0.95, max(0.35, fill_ratio)), source="opencv-contour"))

        return dedupe_proposals(proposals), (width, height)
    finally:
        cleanup()


def dedupe_proposals(proposals: list[Proposal]) -> list[Proposal]:
    ordered = sorted(proposals, key=lambda proposal: proposal.confidence, reverse=True)
    filtered: list[Proposal] = []
    for proposal in ordered:
        if any(iou(proposal, existing) > 0.45 for existing in filtered):
            continue
        filtered.append(proposal)
    return sorted(filtered, key=lambda proposal: (proposal.y, proposal.x))


def iou(lhs: Proposal, rhs: Proposal) -> float:
    lhs_x2 = lhs.x + lhs.width
    lhs_y2 = lhs.y + lhs.height
    rhs_x2 = rhs.x + rhs.width
    rhs_y2 = rhs.y + rhs.height

    intersection_x1 = max(lhs.x, rhs.x)
    intersection_y1 = max(lhs.y, rhs.y)
    intersection_x2 = min(lhs_x2, rhs_x2)
    intersection_y2 = min(lhs_y2, rhs_y2)
    intersection_w = max(0.0, intersection_x2 - intersection_x1)
    intersection_h = max(0.0, intersection_y2 - intersection_y1)
    intersection = intersection_w * intersection_h
    union = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersection
    if union <= 0:
        return 0.0
    return intersection / union


def main() -> int:
    parser = build_argument_parser()
    args = parser.parse_args()

    image_path = Path(args.image).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not image_path.exists():
        print(f"Image not found: {image_path}", file=sys.stderr)
        return 1

    proposals = try_yolo(image_path, args.yolo_model)
    image_size: tuple[int, int] | None = None
    model_version = "opencv-contour"

    if proposals:
        try:
            from PIL import Image  # type: ignore

            with Image.open(image_path) as image:
                image_size = image.size
        except Exception:
            image_size = None
        model_version = f"yolo-obb:{args.yolo_model}"
    else:
        try:
            proposals, image_size = fallback_opencv(image_path)
        except RuntimeError as error:
            print(str(error), file=sys.stderr)
            return 2

    if image_size is None:
        print("Could not determine image size", file=sys.stderr)
        return 3

    payload = {
        "sourceImage": str(image_path),
        "imageSize": {
            "width": image_size[0],
            "height": image_size[1],
        },
        "modelVersion": model_version,
        "proposals": [proposal.to_json(index) for index, proposal in enumerate(proposals, start=1)],
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
