#!/usr/bin/env python3
"""Validate presence of the environment-only Android release signing inputs."""

from __future__ import annotations

import os
from pathlib import Path


REQUIRED = (
    "VOX_ANDROID_STORE_FILE",
    "VOX_ANDROID_STORE_PASSWORD",
    "VOX_ANDROID_KEY_ALIAS",
    "VOX_ANDROID_KEY_PASSWORD",
)


def main() -> None:
    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        raise SystemExit("production signing variables are missing: " + ", ".join(missing))
    store = Path(os.environ["VOX_ANDROID_STORE_FILE"])
    if not store.is_file():
        raise SystemExit("production signing store file does not exist")
    print("Production signing environment is complete; credential values were not printed.")


if __name__ == "__main__":
    main()
