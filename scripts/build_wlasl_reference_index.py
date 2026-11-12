#!/usr/bin/env python3
"""Create a CSV index of locally available WLASL example clips for rehearsal.

The script indexes the user's existing WLASL download; it never copies videos.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, required=True,
                        help="Root of the processed WLASL dataset")
    parser.add_argument("--labels", type=Path, default=Path("assets/ml/labels.json"),
                        help="App labels JSON; defaults to this repository's 351 labels")
    parser.add_argument("--output", type=Path, default=Path("wlasl_rehearsal.csv"),
                        help="Output CSV path")
    parser.add_argument("--per-label", type=int, default=1,
                        help="Maximum number of available examples per app label")
    args = parser.parse_args()

    root = args.dataset.expanduser().resolve()
    videos = root / "videos"
    annotations_path = root / "WLASL_v0.3.json"
    if not videos.is_dir() or not annotations_path.is_file():
        parser.error(f"Expected videos/ and WLASL_v0.3.json under {root}")
    if args.per_label < 1:
        parser.error("--per-label must be at least 1")

    labels = json.loads(args.labels.read_text(encoding="utf-8"))["names"]
    wanted = set(labels)
    annotations = json.loads(annotations_path.read_text(encoding="utf-8"))
    rows: list[dict[str, str]] = []
    available_per_label: dict[str, int] = {}

    for entry in annotations:
        gloss = str(entry.get("gloss", "")).strip()
        if gloss not in wanted:
            continue
        found = 0
        for instance in entry.get("instances", []):
            if found >= args.per_label:
                break
            video_id = str(instance.get("video_id", "")).strip()
            if not video_id or not (videos / f"{video_id}.mp4").is_file():
                continue
            rows.append({
                "gloss": gloss,
                "split": str(instance.get("split", "")),
                "video_id": video_id,
                "video_path": f"videos/{video_id}.mp4",
                "signer_id": str(instance.get("signer_id", "")),
                "source": str(instance.get("source", "")),
            })
            found += 1
        if found:
            available_per_label[gloss] = found

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=(
            "gloss", "split", "video_id", "video_path", "signer_id", "source"))
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda row: (row["gloss"], row["split"], row["video_id"])))

    print(f"Wrote {len(rows)} clip references across {len(available_per_label)} of {len(labels)} app labels")
    print(f"CSV: {args.output.resolve()}")
    print("Video paths are relative to the WLASL dataset directory; no videos were copied.")


if __name__ == "__main__":
    main()
