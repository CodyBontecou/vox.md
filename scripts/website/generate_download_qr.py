#!/usr/bin/env python3
"""Regenerate the committed QR locally; requires ReportLab, not a web service."""

import hashlib
import json

from download_links import QR_METADATA, QR_PATH, destination, load_config


def main():
    try:
        from reportlab.graphics.barcode.qr import QrCodeWidget
        from reportlab.graphics.shapes import Drawing, Rect
        from reportlab.graphics import renderSVG
        from reportlab.lib.colors import white
    except ImportError as error:
        raise SystemExit("QR regeneration requires ReportLab; use the bundled workspace Python runtime") from error
    config = load_config()
    url = destination(config, config["qr_campaign"])
    drawing = Drawing(176, 176)
    drawing.add(Rect(0, 0, 176, 176, fillColor=white, strokeColor=None))
    drawing.add(QrCodeWidget(url, barLevel="M", barBorder=4, barWidth=176, barHeight=176))
    svg = renderSVG.drawToString(drawing).encode()
    QR_PATH.parent.mkdir(parents=True, exist_ok=True)
    QR_PATH.write_bytes(svg)
    QR_METADATA.write_text(json.dumps({"destination": url, "sha256": hashlib.sha256(svg).hexdigest(),
                                       "quiet_zone_modules": 4, "error_correction": "M"}, indent=2) + "\n")
    print(f"Generated local download QR for {url}")


if __name__ == "__main__":
    main()
