import hashlib
import json
import pathlib
import sys


def manifest(apk: pathlib.Path, code: int) -> dict:
    if code <= 0:
        raise ValueError("Android version code must be positive")
    digest = hashlib.sha256()
    with apk.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "code": code,
        "name": f"beta.{code}",
        "notes": "Обновление TrashSquad · Beer Party Studio",
        "sha256": digest.hexdigest(),
        "bytes": apk.stat().st_size,
    }


if __name__ == "__main__":
    print(json.dumps(manifest(pathlib.Path(sys.argv[1]), int(sys.argv[2])), ensure_ascii=False))
