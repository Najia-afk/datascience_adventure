#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ALLOWED_KEYS = {
    "title",
    "short_title",
    "description",
    "image",
    "tags",
    "date",
    "project",
    "order",
}


def _is_non_empty_string(value):
    return isinstance(value, str) and bool(value.strip())


def _validate_tags(tags, file_path):
    errors = []
    if not isinstance(tags, list):
        return [f"{file_path}: 'tags' must be a list."]

    for index, tag in enumerate(tags):
        label = f"{file_path}: tags[{index}]"
        if isinstance(tag, str):
            if not tag.strip():
                errors.append(f"{label} must not be empty.")
            continue

        if not isinstance(tag, dict):
            errors.append(f"{label} must be either a string or an object.")
            continue

        unknown = set(tag.keys()) - {"label", "class", "style"}
        if unknown:
            errors.append(f"{label} has unknown keys: {sorted(unknown)}")

        if not _is_non_empty_string(tag.get("label")):
            errors.append(f"{label}.label is required and must be a non-empty string.")

        if "class" in tag and not _is_non_empty_string(tag.get("class")):
            errors.append(f"{label}.class must be a non-empty string when provided.")

        if "style" in tag and not _is_non_empty_string(tag.get("style")):
            errors.append(f"{label}.style must be a non-empty string when provided.")

    return errors


def validate_sidecar(sidecar_path):
    errors = []
    article_name = sidecar_path.stem

    if article_name == "article_sidecar.example":
        return errors

    if not article_name.startswith("article_"):
        return errors

    html_path = sidecar_path.with_suffix(".html")
    if not html_path.exists():
        errors.append(f"{sidecar_path}: matching template file is missing ({html_path.name}).")

    try:
        with sidecar_path.open("r", encoding="utf-8") as file:
            data = json.load(file)
    except Exception as exc:
        return [f"{sidecar_path}: invalid JSON ({exc})."]

    if not isinstance(data, dict):
        return [f"{sidecar_path}: top-level JSON must be an object."]

    unknown_keys = set(data.keys()) - ALLOWED_KEYS
    if unknown_keys:
        errors.append(f"{sidecar_path}: unknown keys {sorted(unknown_keys)}. Allowed keys: {sorted(ALLOWED_KEYS)}")

    string_keys = ["title", "short_title", "description", "image", "date", "project"]
    for key in string_keys:
        if key in data and not _is_non_empty_string(data[key]):
            errors.append(f"{sidecar_path}: '{key}' must be a non-empty string when provided.")

    if "image" in data and isinstance(data["image"], str) and data["image"] and not data["image"].startswith("/"):
        errors.append(f"{sidecar_path}: 'image' should start with '/'.")

    if "order" in data and not isinstance(data["order"], int):
        errors.append(f"{sidecar_path}: 'order' must be an integer when provided.")

    if "tags" in data:
        errors.extend(_validate_tags(data["tags"], sidecar_path))

    return errors


def main():
    templates_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("app/static/templates")

    if not templates_dir.exists() or not templates_dir.is_dir():
        print(f"Templates directory not found: {templates_dir}")
        return 2

    sidecars = sorted(templates_dir.glob("article_*.json"))
    if not sidecars:
        print("No article sidecar files found. ✅")
        return 0

    all_errors = []
    for sidecar in sidecars:
        all_errors.extend(validate_sidecar(sidecar))

    if all_errors:
        print("Article sidecar validation failed:\n")
        for error in all_errors:
            print(f"- {error}")
        return 1

    print(f"Validated {len(sidecars)} article sidecar file(s). ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
