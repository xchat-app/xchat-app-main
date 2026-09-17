#!/usr/bin/env python3
"""Talk to the Google Play Developer API without any third-party dependency.

Two subcommands:

  next-version-code   print (highest versionCode Play knows about) + 1
  publish             upload an .aab and assign it to a track

Credentials come from a service account JSON, given either as a path in
PLAY_SERVICE_ACCOUNT_JSON_PATH or inline in PLAY_SERVICE_ACCOUNT_JSON.

The version code is read back from Play rather than tracked in the repo. That
is deliberate: pubspec.yaml drifted to 0.1.3+13 while production was on 43,
because the number only ever existed on whichever machine cut the release.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"


def load_service_account():
    path = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON_PATH")
    if path:
        return json.load(open(path))
    raw = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON")
    if raw:
        return json.loads(raw)
    sys.exit("neither PLAY_SERVICE_ACCOUNT_JSON_PATH nor PLAY_SERVICE_ACCOUNT_JSON is set")


def access_token(sa):
    def b64(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=")

    now = int(time.time())
    header = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64(json.dumps({
        "iss": sa["client_email"],
        "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now,
        "exp": now + 3600,
    }).encode())
    signing_input = header + b"." + claims

    with tempfile.NamedTemporaryFile(delete=False) as key_file:
        key_file.write(sa["private_key"].encode())
        key_path = key_file.name
    os.chmod(key_path, 0o600)
    try:
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input, capture_output=True, check=True).stdout
    finally:
        os.unlink(key_path)

    jwt = signing_input + b"." + b64(signature)
    request = urllib.request.Request("https://oauth2.googleapis.com/token", data=urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": jwt.decode(),
    }).encode())
    return json.load(urllib.request.urlopen(request))["access_token"]


def call(token, url, method="GET", body=None, raw=None, content_type=None):
    headers = {"Authorization": f"Bearer {token}"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    elif raw is not None:
        data = raw
        headers["Content-Type"] = content_type or "application/octet-stream"
        headers["Content-Length"] = str(os.fstat(raw.fileno()).st_size)
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            payload = response.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        sys.exit(f"{method} {url}\nHTTP {error.code}: {error.read().decode(errors='replace')}")


def known_version_codes(token, package):
    """Every version code Play has, across tracks and uploaded artifacts."""
    edit = call(token, f"{API}/applications/{package}/edits", "POST")["id"]
    codes = set()
    for track in call(token, f"{API}/applications/{package}/edits/{edit}/tracks").get("tracks", []):
        for release in track.get("releases", []):
            codes.update(int(c) for c in release.get("versionCodes", []))
    for kind, field in (("bundles", "bundle"), ("apks", "apk")):
        try:
            listing = call(token, f"{API}/applications/{package}/edits/{edit}/{kind}")
        except SystemExit:
            continue
        codes.update(item["versionCode"] for item in listing.get(field, []))
    call(token, f"{API}/applications/{package}/edits/{edit}", "DELETE")
    return codes


def cmd_next_version_code(args):
    token = access_token(load_service_account())
    codes = known_version_codes(token, args.package)
    print(max(codes) + 1 if codes else 1)


def cmd_publish(args):
    token = access_token(load_service_account())
    package = args.package

    edit = call(token, f"{API}/applications/{package}/edits", "POST")["id"]
    print(f"edit {edit}", file=sys.stderr)

    with open(args.aab, "rb") as handle:
        bundle = call(
            token,
            f"{UPLOAD}/applications/{package}/edits/{edit}/bundles?uploadType=media",
            "POST", raw=handle)
    version_code = bundle["versionCode"]
    print(f"uploaded versionCode {version_code}", file=sys.stderr)

    release = {"status": args.status, "versionCodes": [str(version_code)]}
    if args.release_name:
        release["name"] = args.release_name
    if args.notes:
        release["releaseNotes"] = [
            {"language": args.notes_language, "text": open(args.notes, encoding="utf-8").read()}
        ]
    if args.status == "inProgress":
        release["userFraction"] = args.user_fraction

    call(token, f"{API}/applications/{package}/edits/{edit}/tracks/{args.track}",
         "PUT", body={"track": args.track, "releases": [release]})
    print(f"assigned to track {args.track} ({args.status})", file=sys.stderr)

    if args.dry_run:
        call(token, f"{API}/applications/{package}/edits/{edit}", "DELETE")
        print("dry run: edit discarded, nothing was published", file=sys.stderr)
        return

    call(token, f"{API}/applications/{package}/edits/{edit}:commit", "POST")
    print(f"committed: versionCode {version_code} is live on {args.track}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package", default="com.oxchat.lite")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("next-version-code").set_defaults(func=cmd_next_version_code)

    publish = sub.add_parser("publish")
    publish.add_argument("--aab", required=True)
    publish.add_argument("--track", default="internal")
    publish.add_argument("--status", default="completed",
                         choices=["completed", "draft", "inProgress", "halted"])
    publish.add_argument("--user-fraction", type=float, default=0.2,
                         help="rollout share, only used when --status inProgress")
    publish.add_argument("--release-name")
    publish.add_argument("--notes", help="path to a release notes file")
    publish.add_argument("--notes-language", default="en-US")
    publish.add_argument("--dry-run", action="store_true",
                         help="upload and assign, then discard the edit instead of committing")
    publish.set_defaults(func=cmd_publish)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
