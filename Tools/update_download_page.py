#!/usr/bin/env python3
"""Point the Geekmaze Vorssaint page at the latest Box upload.

Reads the log from Tools/upload_box.py and rewrites
geekmaze_site/src/data/vorssaint-download.json. The public page changes
after that site is committed and deployed.
"""

import json
import os
import sys
from datetime import datetime


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_upload_log(text):
    version = ""
    filename = ""
    urls = []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("Download: "):
            urls.append(line.split(" ", 1)[1].strip())
            continue
        if " version " in line and not version:
            version = line.rsplit(" version ", 1)[1].strip()
        if "_latest." in line:
            filename = line
    url = urls[-1] if urls else ""
    return version, filename, url


def site_root():
    configured = os.environ.get("GEEKMAZE_SITE", "").strip()
    if configured:
        return os.path.abspath(configured)
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "geekmaze_site"))


def main():
    if len(sys.argv) != 2:
        fail("usage: update_download_page.py <upload-log>")
    log_path = sys.argv[1]
    if not os.path.isfile(log_path):
        fail(f"Upload log was not found: {log_path}")
    with open(log_path, encoding="utf-8") as handle:
        version, filename, url = parse_upload_log(handle.read())
    if not version or not filename or not url.startswith("https://"):
        fail("The Box upload log did not include a version, a latest file, and a download link.")
    root = site_root()
    target = os.path.join(root, "src", "data", "vorssaint-download.json")
    if not os.path.isdir(root):
        fail(f"Geekmaze site was not found at {root}. Set GEEKMAZE_SITE to the site checkout.")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    record = {}
    if os.path.isfile(target):
        with open(target, encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            record = loaded
    record["product"] = record.get("product") or "Vorssaint"
    record["platform"] = record.get("platform") or "macOS Apple Silicon"
    record["version"] = version
    record["fileName"] = filename
    record["url"] = url
    record["updated"] = datetime.now().astimezone().isoformat(timespec="seconds")
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(record, handle, indent=2)
        handle.write("\n")
    print(f"Geekmaze download page now points at {url}")
    print(f"Wrote {target}")


if __name__ == "__main__":
    main()
