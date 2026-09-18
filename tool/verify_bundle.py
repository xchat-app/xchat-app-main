#!/usr/bin/env python3
"""Check a release .aab or .apk before it goes anywhere.

Version 44 shipped to every user and died on launch because
libnostr_mls_package.so was not in it. Nothing caught that: CargoKit printed
one line and returned, Gradle exited 0, the artifact was signed with the right
key, and the release passed every check that existed. Two more artifacts that
week were wrong in the same shape — a year-old committed binary shadowing a
fresh build, and libraries linked for 4 KB pages.

All three share it: the build succeeded and the output was not what anyone
believed it was. So this looks at the file itself.

    python3 tool/verify_bundle.py build/app/outputs/bundle/release/app-release.aab

Exits non-zero on the first thing that would reach a user.
"""

import argparse
import re
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

# Libraries every release is expected to carry, per ABI. Written down rather
# than inferred: the point is to notice when one stops being built, and a list
# derived from the artifact under test could never do that.
EXPECTED = Path(__file__).with_name("expected_native_libs.txt")

# The certificate registered in 0xchat.com/.well-known/assetlinks.json. Signing
# with anything else does not fail the upload — it quietly stops Android App
# Links verifying, so every invite link opens a browser instead of the app.
SIGNING_SHA256 = ("CC:E2:D4:08:11:66:90:30:B9:E2:3E:C1:BA:74:11:40:"
                  "AA:FE:63:E0:E0:46:0A:86:B3:F5:D3:58:CC:2C:8F:5F")

# 16 KB pages exist only on 64-bit devices, so only these need the alignment.
PAGE_ALIGNED_ABIS = {"arm64-v8a", "x86_64"}
REQUIRED_ALIGNMENT = 0x4000

failures = []
notes = []


def fail(message):
    failures.append(message)


def load_expected():
    if not EXPECTED.is_file():
        fail(f"{EXPECTED.name} is missing; nothing to check the library list against")
        return set()
    return {
        line.strip()
        for line in EXPECTED.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }


def lib_entries(bundle):
    """Map abi -> {library name: zip entry}, for an .aab or an .apk."""
    found = {}
    for name in bundle.namelist():
        # base/lib/<abi>/x.so in a bundle, lib/<abi>/x.so in an apk
        match = re.match(r"(?:[^/]+/)?lib/([^/]+)/([^/]+\.so)$", name)
        if match and "BUNDLE-METADATA" not in name:
            found.setdefault(match.group(1), {})[match.group(2)] = name
    return found


def max_load_alignment(data):
    """Largest p_align over the ELF's PT_LOAD segments."""
    if data[:4] != b"\x7fELF":
        return None
    is64 = data[4] == 2
    fmt = "<Q" if is64 else "<I"
    phoff = struct.unpack_from(fmt, data, 0x20 if is64 else 0x1C)[0]
    phentsize = struct.unpack_from("<H", data, 0x36 if is64 else 0x2A)[0]
    phnum = struct.unpack_from("<H", data, 0x38 if is64 else 0x2C)[0]
    best = 0
    for i in range(phnum):
        off = phoff + i * phentsize
        if struct.unpack_from("<I", data, off)[0] == 1:  # PT_LOAD
            align_off = off + (0x30 if is64 else 0x1C)
            best = max(best, struct.unpack_from(fmt, data, align_off)[0])
    return best


def check_libraries(bundle, expected):
    abis = lib_entries(bundle)
    if not abis:
        fail("the artifact contains no native libraries at all")
        return abis
    # A --target-platform build leaves stale odds and ends under the ABIs it did
    # not target. An ABI without the Flutter engine was not built this time, so
    # holding it to the full list would report missing libraries that were never
    # meant to be there.
    built = {abi: libs for abi, libs in abis.items() if "libflutter.so" in libs}
    skipped = sorted(set(abis) - set(built))
    if skipped:
        notes.append("not built in this artifact, so not checked: " + ", ".join(skipped))
    abis = built or abis
    print(f"{'ABI':14} {'libs':>5}  missing")
    print("-" * 60)
    for abi in sorted(abis):
        present = set(abis[abi])
        missing = sorted(expected - present)
        print(f"{abi:14} {len(present):>5}  {', '.join(missing) if missing else '-'}")
        for name in missing:
            fail(f"{abi}: {name} is not in the artifact")
        extra = sorted(present - expected)
        if extra:
            notes.append(f"{abi} carries libraries not on the expected list: {', '.join(extra)}")
    return abis


def check_alignment(bundle, abis):
    print(f"\n{'library':44} {'align':>8}")
    print("-" * 60)
    for abi in sorted(set(abis) & PAGE_ALIGNED_ABIS):
        for name, entry in sorted(abis[abi].items()):
            align = max_load_alignment(bundle.read(entry))
            if align is None:
                fail(f"{abi}/{name} is not an ELF file")
                continue
            ok = align >= REQUIRED_ALIGNMENT
            print(f"{abi + '/' + name:44} {hex(align):>8}  {'ok' if ok else 'NOT 16 KB'}")
            if not ok:
                fail(f"{abi}/{name} links its LOAD segments at {hex(align)}, "
                     f"below the {hex(REQUIRED_ALIGNMENT)} Android 15+ wants")


def check_signature(path, bundle):
    sig = next((n for n in bundle.namelist()
                if re.match(r"META-INF/.*\.(RSA|DSA|EC)$", n)), None)
    if sig is None:
        # A bundle carries a jar signature here. An APK signed with scheme v2
        # or later keeps it in the APK Signing Block instead, where this cannot
        # see it — say so rather than calling a signed APK unsigned.
        if path.suffix == ".apk":
            notes.append("APK signature lives in the v2 signing block; "
                         "check the certificate on the .aab instead")
        else:
            fail("the artifact is unsigned")
        return
    try:
        out = subprocess.run(["keytool", "-printcert"], input=bundle.read(sig),
                             capture_output=True, check=True).stdout.decode()
    except (OSError, subprocess.CalledProcessError) as error:
        notes.append(f"could not read the certificate ({error}); signature unchecked")
        return
    match = re.search(r"SHA256:\s*([0-9A-F:]+)", out)
    actual = match.group(1) if match else "?"
    print(f"\nsigning SHA-256  {actual}")
    if actual != SIGNING_SHA256:
        fail(f"signed with {actual}, not the certificate in assetlinks.json")


def check_version(bundle):
    entry = next((n for n in bundle.namelist()
                  if n.endswith("manifest/AndroidManifest.xml")), None)
    if entry is None:
        return
    data = bundle.read(entry)
    text = data.decode("utf-8", "ignore")
    for field in ("versionCode", "versionName"):
        i = text.find(field)
        if i < 0:
            continue
        m = re.search((field + r"\x1a(.)").encode(), data[i:i + len(field) + 20])
        if m:
            length = m.group(1)[0]
            value = data[i + m.end():i + m.end() + length].decode("utf-8", "ignore")
            print(f"{field:16} {value}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("artifact", help="path to the .aab or .apk")
    args = parser.parse_args()

    path = Path(args.artifact)
    if not path.is_file():
        sys.exit(f"no such file: {path}")
    print(f"{path}  ({path.stat().st_size // (1024 * 1024)} MB)\n")

    expected = load_expected()
    with zipfile.ZipFile(path) as bundle:
        check_version(bundle)
        print()
        abis = check_libraries(bundle, expected)
        check_alignment(bundle, abis)
        check_signature(path, bundle)

    for note in notes:
        print(f"\nnote: {note}")

    if failures:
        print(f"\n{len(failures)} problem(s) that would reach a user:")
        for problem in failures:
            print(f"  - {problem}")
        sys.exit(1)
    print("\nartifact looks like what it is supposed to be.")


if __name__ == "__main__":
    main()
