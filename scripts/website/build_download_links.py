#!/usr/bin/env python3
"""Apply page-specific App Store destinations and verify the committed QR asset."""

import argparse
import hashlib
import json

from download_links import ROOT, QR_PATH, QR_METADATA, decorate_html, destination, load_config, page_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    config = load_config()
    expected_qr = destination(config, config["qr_campaign"])
    if not QR_PATH.exists() or not QR_METADATA.exists():
        raise SystemExit("Generate the download QR: python3 scripts/website/generate_download_qr.py")
    qr = json.loads(QR_METADATA.read_text())
    if qr["destination"] != expected_qr or qr["sha256"] != hashlib.sha256(QR_PATH.read_bytes()).hexdigest():
        raise SystemExit("QR destination changed; run python3 scripts/website/generate_download_qr.py")
    stale = []
    count = 0
    for path in sorted((ROOT / "website").rglob("*.html")):
        original = path.read_text()
        output = decorate_html(original, page_path(path), config)
        if original != output:
            if args.check:
                stale.append(str(path.relative_to(ROOT)))
            else:
                path.write_text(output)
        count += 1
    if stale:
        raise SystemExit("Run npm run website:build; stale download links:\n" + "\n".join(stale))
    status = "enabled" if config.get("verified_campaign_link") else "disabled (direct App Store links)"
    print(f"{'Checked' if args.check else 'Built'} download links on {count} pages; attribution {status}")


if __name__ == "__main__":
    main()
