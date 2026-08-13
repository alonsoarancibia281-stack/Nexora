#!/usr/bin/env python3
"""Folds Nexora's native Android code into the generated wrapper.

The repository does not carry an `android/` directory: the CI regenerates it
with `flutter create` on every build, which keeps the Gradle and AGP plumbing
current without anyone maintaining it by hand. Everything Nexora actually
writes in Kotlin lives in `android_native/`, and this script copies it into the
freshly generated wrapper and patches the manifest.

Idempotent: running it twice changes nothing the second time.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

PACKAGE = "ai.nexora.nexora_markets_ai"
SOURCE = Path("android_native")
KOTLIN_ROOT = Path("android/app/src/main/kotlin") / Path(*PACKAGE.split("."))
MANIFEST = Path("android/app/src/main/AndroidManifest.xml")

PERMISSIONS = [
    # Market data, news and the Supabase function.
    "android.permission.INTERNET",
    # The floating readout drawn over other apps.
    "android.permission.SYSTEM_ALERT_WINDOW",
    # Keeping the council alive once Nexora is no longer in front.
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    "android.permission.POST_NOTIFICATIONS",
]

SERVICE = """
        <service
            android:name=".OverlayService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Lectura flotante del veredicto sobre la app de trading" />
        </service>
"""


def copy_sources() -> None:
    if not SOURCE.is_dir():
        raise SystemExit(f"missing {SOURCE}/")
    KOTLIN_ROOT.mkdir(parents=True, exist_ok=True)
    sources = sorted(SOURCE.glob("*.kt"))
    if not sources:
        raise SystemExit(f"no Kotlin sources in {SOURCE}/")
    for path in sources:
        # Overwrites the MainActivity the generator just wrote.
        shutil.copy2(path, KOTLIN_ROOT / path.name)
        print(f"  {path} → {KOTLIN_ROOT / path.name}")


def patch_manifest() -> None:
    if not MANIFEST.is_file():
        raise SystemExit(f"missing {MANIFEST}")
    text = MANIFEST.read_text()

    opening = re.search(r"<manifest\b[^>]*>", text)
    if opening is None:
        raise SystemExit("could not find the <manifest> element")

    pending = [
        name for name in PERMISSIONS
        if f'android:name="{name}"' not in text
    ]
    if pending:
        block = "".join(
            f'\n    <uses-permission android:name="{name}" />' for name in pending
        )
        text = text[: opening.end()] + block + text[opening.end():]
        for name in pending:
            print(f"  + permiso {name}")

    if 'android:name=".OverlayService"' not in text:
        closing = text.rfind("</application>")
        if closing < 0:
            raise SystemExit("could not find </application>")
        text = text[:closing] + SERVICE + text[closing:]
        print("  + servicio OverlayService")

    MANIFEST.write_text(text)


def main() -> int:
    print("Integrando el código nativo de Nexora…")
    copy_sources()
    patch_manifest()
    print("Listo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
