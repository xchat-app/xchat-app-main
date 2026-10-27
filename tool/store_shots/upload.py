"""Replace the Play phone screenshots with build/store-shots/framed/<lang>/*.png.

Each app language fills every store listing in that language (en → en-US and
any other English listing, es → es-419 and es-ES, …). Listings in languages
without a set keep nothing of their own, so Play shows them the default
language's (en-US) screenshots.

Dry run by default: uploads into an edit, validates it, then discards it.
--commit publishes, which sends the listing for review.

  PLAY_SERVICE_ACCOUNT_JSON_PATH=… python3 tool/store_shots/upload.py [--commit] [lang…]
"""

import argparse
import os
import ssl
import sys
import time
import urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import play_publish as play  # noqa: E402

PACKAGE = "com.oxchat.lite"
FRAMED = os.path.join(os.path.dirname(__file__), "..", "..", "build", "store-shots", "framed")
# App i18n code → the store listing languages it covers, when the listing exists.
LISTINGS = {
    "en": ["en-US", "en-GB", "en-AU", "en-CA", "en-IN", "en-SG", "en-ZA"],
    "fa": ["fa-IR", "fa", "fa-AE", "fa-AF"],
    "ar": ["ar"],
    "fr": ["fr-FR", "fr-CA"],
    "es": ["es-419", "es-ES", "es-US"],
    "ru": ["ru-RU"],
    "zh": ["zh-CN"],
    "pt": ["pt-BR", "pt-PT"],
}


def retry(fn, *args, **kwargs):
    # The proxy on this machine drops TLS now and then; Play errors still exit.
    for attempt in range(6):
        try:
            return fn(*args, **kwargs)
        except (urllib.error.URLError, ssl.SSLError, ConnectionError, TimeoutError) as error:
            if attempt == 5:
                raise
            print(f"  retrying after {error}", file=sys.stderr)
            time.sleep(3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--commit", action="store_true")
    parser.add_argument("langs", nargs="*", default=list(LISTINGS))
    args = parser.parse_args()

    token = play.access_token(play.load_service_account())
    base = f"{play.API}/applications/{PACKAGE}/edits"
    edit = retry(play.call, token, base, "POST")["id"]
    existing = {item["language"] for item in retry(play.call, token, f"{base}/{edit}/listings").get("listings", [])}

    for lang in args.langs:
        folder = os.path.join(FRAMED, lang)
        shots = sorted(f for f in os.listdir(folder) if f.endswith(".png")) if os.path.isdir(folder) else []
        if len(shots) < 2:
            sys.exit(f"{lang}: {len(shots)} screenshots in {folder}, Play needs at least 2")
        for listing in [code for code in LISTINGS[lang] if code in existing]:
            images = f"{base}/{edit}/listings/{listing}/phoneScreenshots"
            retry(play.call, token, images, "DELETE")
            upload = f"{play.UPLOAD}/applications/{PACKAGE}/edits/{edit}/listings/{listing}/phoneScreenshots?uploadType=media"
            for name in shots:
                # Opened per attempt: a dropped upload leaves the handle at the end.
                def send(path=os.path.join(folder, name)):
                    with open(path, "rb") as handle:
                        return play.call(token, upload, "POST", raw=handle, content_type="image/png")
                retry(send)
            print(f"{listing}: {len(shots)} screenshots from {lang}")

    print("validate:", retry(play.call, token, f"{base}/{edit}:validate", "POST"))
    if args.commit:
        print("commit:", retry(play.call, token, f"{base}/{edit}:commit", "POST"))
    else:
        retry(play.call, token, f"{base}/{edit}", "DELETE")
        print("dry run: edit discarded")


if __name__ == "__main__":
    main()
