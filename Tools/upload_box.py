#!/usr/bin/env python3
"""Upload a finished Vorssaint package to Box.

The file lands in the folder named by GEEKPLAY_BOX_FOLDER_ID. Each upload
writes a dated file and replaces the matching latest file, then opens a
view-and-download link for both.
"""

import base64
import hashlib
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime

API = "https://api.box.com/2.0"
UPLOAD = "https://upload.box.com/api/2.0"
# Box requires a chunked session once a file reaches 20 MiB.
CHUNKED_MIN = 20_000_000
TOKEN_URL = "https://api.box.com/oauth2/token"


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def config_path():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "local.env")


def load_env(path):
    values = {}
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def write_env(path, updates):
    lines = []
    seen = set()
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            key = raw.split("=", 1)[0].strip() if "=" in raw and not raw.lstrip().startswith("#") else ""
            if key in updates:
                lines.append(f"{key}={updates[key]}\n")
                seen.add(key)
            else:
                lines.append(raw if raw.endswith("\n") else raw + "\n")
    for key, value in updates.items():
        if key not in seen:
            lines.append(f"{key}={value}\n")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.writelines(lines)


def ssl_context():
    """Trust the usual CA bundle. python.org builds on macOS ship without one."""
    configured = os.environ.get("SSL_CERT_FILE", "")
    if configured and os.path.isfile(configured):
        return ssl.create_default_context(cafile=configured)
    default = ssl.get_default_verify_paths().openssl_cafile or ""
    if not default or os.path.isfile(default):
        return ssl.create_default_context()
    for candidate in ("/etc/ssl/cert.pem",):
        if os.path.isfile(candidate):
            return ssl.create_default_context(cafile=candidate)
    try:
        import certifi
    except ImportError:
        certifi = None
    if certifi is not None and os.path.isfile(certifi.where()):
        return ssl.create_default_context(cafile=certifi.where())
    return ssl.create_default_context()


def request(method, url, token, payload=None, headers=None, body=None, content_type=None):
    hdrs = {}
    if token:
        hdrs["Authorization"] = f"Bearer {token}"
    data = body
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    elif content_type:
        hdrs["Content-Type"] = content_type
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=300, context=ssl_context()) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read()


def error_message(body, headers=None):
    text = ""
    try:
        parsed = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        text = body.decode("utf-8", errors="replace")[:500].strip()
    else:
        code = parsed.get("code") or parsed.get("error") or "error"
        message = parsed.get("message") or parsed.get("error_description") or ""
        text = f"{code}: {message}".strip()
    if text:
        return text
    if headers:
        auth = headers.get("WWW-Authenticate") or headers.get("www-authenticate") or ""
        if auth:
            return auth[:500]
    return "Box returned an empty error."


def form_post(url, fields):
    body = "&".join(
        f"{urllib.request.quote(key)}={urllib.request.quote(value)}"
        for key, value in fields.items()
    ).encode("utf-8")
    status, _headers, payload = request(
        "POST",
        url,
        token=None,
        body=body,
        content_type="application/x-www-form-urlencoded",
    )
    if status != 200:
        fail(f"Box rejected the token request ({status}): {error_message(payload, _headers)}")
    return json.loads(payload.decode("utf-8"))


def access_token(env, path):
    client_id = env.get("GEEKPLAY_BOX_CLIENT_ID", "")
    client_secret = env.get("GEEKPLAY_BOX_CLIENT_SECRET", "")
    enterprise = env.get("GEEKPLAY_BOX_ENTERPRISE_ID", "")
    refresh = env.get("GEEKPLAY_BOX_REFRESH_TOKEN", "")
    if client_id and client_secret and enterprise:
        granted = form_post(
            TOKEN_URL,
            {
                "grant_type": "client_credentials",
                "client_id": client_id,
                "client_secret": client_secret,
                "box_subject_type": "enterprise",
                "box_subject_id": enterprise,
            },
        )
        return granted["access_token"]
    if client_id and client_secret and refresh:
        granted = form_post(
            TOKEN_URL,
            {
                "grant_type": "refresh_token",
                "client_id": client_id,
                "client_secret": client_secret,
                "refresh_token": refresh,
            },
        )
        updates = {"GEEKPLAY_BOX_ACCESS_TOKEN": granted["access_token"]}
        if granted.get("refresh_token"):
            updates["GEEKPLAY_BOX_REFRESH_TOKEN"] = granted["refresh_token"]
        write_env(path, updates)
        return granted["access_token"]
    token = env.get("GEEKPLAY_BOX_ACCESS_TOKEN", "")
    if not token:
        fail(
            "Box upload needs GEEKPLAY_BOX_ACCESS_TOKEN, or a client id, secret, and refresh token."
        )
    return token


def folder_items(folder_id, token):
    marker = ""
    while True:
        url = (
            f"{API}/folders/{urllib.request.quote(folder_id)}/items"
            "?limit=1000&fields=id,name,type&usemarker=true"
        )
        if marker:
            url += "&marker=" + urllib.request.quote(marker)
        status, _headers, body = request("GET", url, token)
        if status != 200:
            fail(f"Box could not list the folder ({status}): {error_message(body, _headers)}")
        parsed = json.loads(body.decode("utf-8"))
        for entry in parsed.get("entries", []):
            yield entry
        marker = parsed.get("next_marker") or ""
        if not marker:
            return


def find_file(folder_id, name, token):
    for entry in folder_items(folder_id, token):
        if entry.get("type") == "file" and entry.get("name") == name:
            return entry["id"]
    return ""


def conflict_id(body):
    try:
        parsed = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return ""
    conflicts = parsed.get("context_info", {}).get("conflicts")
    if isinstance(conflicts, dict):
        return str(conflicts.get("id") or "")
    if isinstance(conflicts, list) and conflicts:
        return str(conflicts[0].get("id") or "")
    return ""


def sha1_b64(data):
    return base64.b64encode(hashlib.sha1(data).digest()).decode("ascii")


def file_sha1_b64(path):
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return base64.b64encode(digest.digest()).decode("ascii")


def multipart_body(attributes, filename, data):
    boundary = "geekplay" + uuid.uuid4().hex
    head = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="attributes"\r\n'
        "Content-Type: application/json\r\n\r\n"
        f"{json.dumps(attributes)}\r\n"
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode("utf-8")
    tail = f"\r\n--{boundary}--\r\n".encode("utf-8")
    return head + data + tail, f"multipart/form-data; boundary={boundary}"


def simple_upload(path, folder_id, remote_name, token, file_id):
    with open(path, "rb") as handle:
        data = handle.read()
    if file_id:
        url = f"{UPLOAD}/files/{file_id}/content"
        attributes = {"name": remote_name}
    else:
        url = f"{UPLOAD}/files/content"
        attributes = {"name": remote_name, "parent": {"id": folder_id}}
    body, content_type = multipart_body(attributes, remote_name, data)
    status, _headers, payload = request(
        "POST", url, token, body=body, content_type=content_type
    )
    if status == 409 and not file_id:
        existing = conflict_id(payload)
        if existing:
            return simple_upload(path, folder_id, remote_name, token, existing)
    if status not in (200, 201):
        fail(f"Box rejected the upload ({status}): {error_message(payload, _headers)}")
    return json.loads(payload.decode("utf-8"))


def upload_part(url, token, chunk, offset, total):
    end = offset + len(chunk) - 1
    headers = {
        "Digest": "sha=" + sha1_b64(chunk),
        "Content-Range": f"bytes {offset}-{end}/{total}",
        "Content-Type": "application/octet-stream",
    }
    delay = 1
    for _attempt in range(5):
        status, _response_headers, payload = request(
            "PUT", url, token, body=chunk, headers=headers
        )
        if status == 200:
            return json.loads(payload.decode("utf-8"))["part"]
        if status not in (429, 500, 502, 503, 504):
            fail(f"Box rejected an upload part ({status}): {error_message(payload, _response_headers)}")
        time.sleep(delay)
        delay = min(delay * 2, 30)
    fail("Box kept failing an upload part.")


def chunked_upload(path, folder_id, remote_name, token, file_id):
    size = os.path.getsize(path)
    if file_id:
        url = f"{UPLOAD}/files/{file_id}/upload_sessions"
        payload = {"file_size": size, "file_name": remote_name}
    else:
        url = f"{UPLOAD}/files/upload_sessions"
        payload = {"folder_id": folder_id, "file_size": size, "file_name": remote_name}
    status, _headers, body = request("POST", url, token, payload=payload)
    if status == 409 and not file_id:
        existing = conflict_id(body)
        if existing:
            return chunked_upload(path, folder_id, remote_name, token, existing)
    if status != 201:
        fail(f"Box did not open an upload session ({status}): {error_message(body, _headers)}")
    session = json.loads(body.decode("utf-8"))
    endpoints = session["session_endpoints"]
    part_size = int(session["part_size"])
    parts = []
    offset = 0
    committed = False
    try:
        with open(path, "rb") as handle:
            while offset < size:
                chunk = handle.read(part_size)
                part = upload_part(endpoints["upload_part"], token, chunk, offset, size)
                parts.append(
                    {
                        "part_id": part.get("part_id") or part.get("id"),
                        "offset": part["offset"],
                        "size": part["size"],
                    }
                )
                offset += len(chunk)
        commit_body = {"parts": parts}
        headers = {"Digest": "sha=" + file_sha1_b64(path)}
        for _attempt in range(10):
            status, response_headers, payload = request(
                "POST",
                endpoints["commit"],
                token,
                payload=commit_body,
                headers=headers,
            )
            if status in (200, 201):
                committed = True
                return json.loads(payload.decode("utf-8"))
            if status != 202:
                fail(f"Box did not commit the upload ({status}): {error_message(payload, response_headers)}")
            retry_after = response_headers.get("Retry-After") or response_headers.get("retry-after") or 2
            time.sleep(int(retry_after))
        fail("Box did not finish processing the upload.")
    finally:
        if not committed and endpoints.get("abort"):
            request("DELETE", endpoints["abort"], token)


def uploaded_file(parsed):
    entries = parsed.get("entries")
    if entries:
        return entries[0]
    if parsed.get("type") == "file":
        return parsed
    fail("Box did not return the uploaded file.")


def upload_stamp(when=None):
    """Local time as ddmmyyyy_hhmmx, with x as a for AM and p for PM."""
    when = when or datetime.now().astimezone()
    hour = when.hour % 12 or 12
    marker = "a" if when.hour < 12 else "p"
    return f"{when.day:02d}{when.month:02d}{when.year:04d}_{hour:02d}{when.minute:02d}{marker}"


def stamp_in_name(path):
    """A compiled file already named with ddmmyyyy_hhmmx keeps that stamp."""
    stem = os.path.splitext(os.path.basename(path))[0]
    found = re.search(r"_(\d{8}_\d{4}[ap])$", stem, re.IGNORECASE)
    if not found:
        return ""
    return found.group(1).lower()


def pe_machine(path):
    with open(path, "rb") as handle:
        handle.seek(0x3C)
        pe_offset = int.from_bytes(handle.read(4), "little")
        handle.seek(pe_offset)
        if handle.read(4) != b"PE\0\0":
            return None
        return int.from_bytes(handle.read(2), "little")


def architecture_label(path):
    """x64, arm64, or x86. An empty string means the architecture was not recognized."""
    lower = os.path.basename(path).lower()
    if lower.endswith(".exe"):
        machine = pe_machine(path)
        if machine == 0x8664:
            return "x64"
        if machine == 0xAA64:
            return "arm64"
        if machine == 0x14C:
            return "x86"
    if "aarch64" in lower or "arm64" in lower:
        return "arm64"
    if "x86_64" in lower or "amd64" in lower:
        return "x64"
    if "i686" in lower or "i386" in lower:
        return "x86"
    return ""


def package_stem(path):
    """Vorssaint-macOS for a disk image or zip of the app."""
    extension = os.path.splitext(path)[1].lower()
    if extension in {".dmg", ".zip"}:
        return "Vorssaint-macOS"
    return "Vorssaint"


def package_names(path, when=None):
    arch = architecture_label(path)
    arch_part = f"_{arch}" if arch else ""
    stamp = stamp_in_name(path) or upload_stamp(when)
    extension = os.path.splitext(path)[1].lower() or ".exe"
    stem = package_stem(path)
    dated = f"{stem}{arch_part}_{stamp}{extension}"
    latest = f"{stem}{arch_part}_latest{extension}"
    return dated, latest


def copy_file(file_id, folder_id, name, token):
    status, _headers, body = request(
        "POST",
        f"{API}/files/{file_id}/copy",
        token,
        payload={"parent": {"id": folder_id}, "name": name},
    )
    if status in (200, 201):
        return json.loads(body.decode("utf-8"))
    if status == 409:
        return ""
    fail(f"Box could not copy the latest file ({status}): {error_message(body, _headers)}")


def publish_latest(source, folder_id, dated_id, latest_name, token):
    copied = copy_file(dated_id, folder_id, latest_name, token)
    if copied:
        return copied
    existing = find_file(folder_id, latest_name, token)
    if not existing:
        fail(f"Box already has {latest_name}, but its file id was not found.")
    size = os.path.getsize(source)
    if size >= CHUNKED_MIN:
        result = chunked_upload(source, folder_id, latest_name, token, existing)
    else:
        result = simple_upload(source, folder_id, latest_name, token, existing)
    return uploaded_file(result)


def direct_link_allowed(url):
    """True when a shared direct link returns the file, not an HTML error page."""
    req = urllib.request.Request(url, headers={"Range": "bytes=0-0"}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=60, context=ssl_context()) as response:
            sample = response.read(4096)
            content_type = (response.headers.get("Content-Type") or "").lower()
            status = response.status
    except urllib.error.HTTPError as error:
        sample = error.read(4096)
        content_type = (error.headers.get("Content-Type") or "").lower()
        status = error.code
    except urllib.error.URLError:
        return False
    if b"not allowed to use direct links" in sample or "text/html" in content_type:
        return False
    return status in (200, 206)


def share_file(file_id, token):
    """Open a shared link with view and download, and return a URL that can fetch the file."""
    url = f"{API}/files/{urllib.request.quote(str(file_id))}?fields=shared_link"
    status, _headers, body = request(
        "PUT",
        url,
        token,
        payload={
            "shared_link": {
                "access": "open",
                "permissions": {
                    "can_preview": True,
                    "can_download": True,
                    "can_edit": False,
                },
            }
        },
    )
    if status != 200:
        fail(f"Box did not share the file ({status}): {error_message(body, _headers)}")
    link = json.loads(body.decode("utf-8")).get("shared_link") or {}
    if not link.get("download_url") and not link.get("url"):
        status, _headers, body = request("GET", url, token)
        if status != 200:
            fail(f"Box did not return the shared link ({status}): {error_message(body, _headers)}")
        link = json.loads(body.decode("utf-8")).get("shared_link") or {}
    permissions = link.get("permissions") or {}
    if permissions.get("can_preview") is not True or permissions.get("can_download") is not True:
        fail("Box did not enable view and download on the shared link.")
    direct = link.get("download_url") or ""
    page = link.get("url") or ""
    if direct and direct_link_allowed(direct):
        return direct
    if page:
        return page
    fail("Box did not return a shareable download URL.")


def main():
    if len(sys.argv) not in (3, 4):
        fail("usage: upload_box.py <file> <version> [local.env]")
    source = sys.argv[1]
    version = sys.argv[2]
    if not os.path.isfile(source):
        fail(f"Nothing to upload: {source}")
    path = sys.argv[3] if len(sys.argv) == 4 else config_path()
    if not os.path.isfile(path):
        fail(f"Box upload needs {path}.")
    env = load_env(path)
    folder_id = env.get("GEEKPLAY_BOX_FOLDER_ID", "")
    if not folder_id:
        fail(f"Box upload needs GEEKPLAY_BOX_FOLDER_ID in {path}.")
    token = access_token(env, path)
    name, latest_name = package_names(source)
    file_id = find_file(folder_id, name, token)
    size = os.path.getsize(source)
    if size >= CHUNKED_MIN:
        result = chunked_upload(source, folder_id, name, token, file_id)
    else:
        result = simple_upload(source, folder_id, name, token, file_id)
    uploaded = uploaded_file(result)
    latest = publish_latest(source, folder_id, uploaded["id"], latest_name, token)
    print(f"{name} version {version}")
    print(f"Download: {share_file(uploaded['id'], token)}")
    print(latest_name)
    print(f"Download: {share_file(latest['id'], token)}")


if __name__ == "__main__":
    main()
