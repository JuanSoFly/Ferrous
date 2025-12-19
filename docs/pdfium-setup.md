# PDFium Setup Guide (Android)

This document explains how to bundle the **PDFium** native library (`libpdfium.so`) into the Android app so that the Rust `pdfium-render` crate can render PDFs.

Ferrous loads PDFium at runtime from Rust (see `rust/src/api/pdf.rs`), so the Android package **must** include `libpdfium.so` for every ABI you intend to ship/run on.

## What breaks when it’s missing

When PDFium is not bundled for the current device ABI, you’ll see a runtime error indicating that `libpdfium.so` can’t be loaded, for example:

```
Failed to bind to pdfium library:
dlopen failed: library "libpdfium.so" not found
```

## Recommended approach: prebuilt PDFium binaries

### Step 1: Decide which Android ABIs you need

At minimum for real devices you should ship **`arm64-v8a`**. Add others based on your support/dev needs:

- `arm64-v8a` (required): almost all modern phones/tablets
- `armeabi-v7a` (optional): older 32‑bit devices
- `x86_64` (recommended for dev): Android emulator images
- `x86` (rare): older emulator images

### Step 2: Download the matching archives

Download from `bblanchon/pdfium-binaries`.

Tip for reproducible builds: prefer pinning to a specific release tag (instead of `latest`) once you know it works for you.

| ABI | Archive | Use case |
|---|---|---|
| `arm64-v8a` | `pdfium-android-arm64.tgz` | Modern 64‑bit devices |
| `armeabi-v7a` | `pdfium-android-arm.tgz` | Legacy 32‑bit devices |
| `x86_64` | `pdfium-android-x64.tgz` | 64‑bit Android emulators |
| `x86` | `pdfium-android-x86.tgz` | 32‑bit Android emulators |

Release downloads (latest):

- `pdfium-android-arm64.tgz`: `https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-android-arm64.tgz`
- `pdfium-android-arm.tgz`: `https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-android-arm.tgz`
- `pdfium-android-x64.tgz`: `https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-android-x64.tgz`
- `pdfium-android-x86.tgz`: `https://github.com/bblanchon/pdfium-binaries/releases/latest/download/pdfium-android-x86.tgz`

### Step 3: Create the `jniLibs` folder structure

From the project root:

```bash
mkdir -p android/app/src/main/jniLibs/arm64-v8a
mkdir -p android/app/src/main/jniLibs/armeabi-v7a
mkdir -p android/app/src/main/jniLibs/x86_64
mkdir -p android/app/src/main/jniLibs/x86
```

You only need folders for the ABIs you’re actually using.

### Step 4: Extract and copy `libpdfium.so`

Each `.tgz` typically contains:

```
lib/
  libpdfium.so    ← copy this file
include/
  ...             ← headers (not needed at runtime)
```

Example (arm64‑v8a):

```bash
tar -xzf pdfium-android-arm64.tgz
cp lib/libpdfium.so android/app/src/main/jniLibs/arm64-v8a/
```

Repeat for the other ABIs, copying into the matching `jniLibs/<abi>/` folder.

### Step 5: Build (when you’re ready)

This guide does not require changing Gradle files: placing `libpdfium.so` under `android/app/src/main/jniLibs/<abi>/` is enough for Flutter/Android to package it.

When you’re ready to produce artifacts:

- Split APKs (recommended to avoid a fat APK): `flutter build apk --split-per-abi`
- Single (fat) APK: `flutter build apk --release`
- App Bundle: `flutter build appbundle --release`

## Automation: setup script (recommended)

This repo includes a setup script you can run from the project root:

- `scripts/setup-pdfium-android.sh`

It downloads the selected ABI archives and installs `libpdfium.so` into `android/app/src/main/jniLibs`.

Note: this repo ignores `android/app/src/main/jniLibs/**/libpdfium.so` by default to avoid accidentally committing large binaries. If you intentionally want to commit the `.so` files, use `git add -f`.

Examples:

```bash
# Real devices (default): arm64-v8a + armeabi-v7a
bash scripts/setup-pdfium-android.sh

# Emulator-friendly: add x86_64
PDFIUM_ABIS="arm64-v8a,armeabi-v7a,x86_64" bash scripts/setup-pdfium-android.sh

# Pin to a specific release tag (example format used by pdfium-binaries)
PDFIUM_RELEASE="chromium/XXXX" bash scripts/setup-pdfium-android.sh
```

## APK size impact (rule of thumb)

The exact size varies per `pdfium-binaries` release and ABI, but expect **a few MB per ABI** for `libpdfium.so`, and the total size to scale roughly linearly with the number of ABIs you bundle.

If you want to keep download/install size small, prefer:

- `flutter build apk --split-per-abi` for APKs, or
- an App Bundle (`flutter build appbundle`) so Play can serve the right ABI split.

## Troubleshooting

### `dlopen failed: library "libpdfium.so" not found`

- Confirm the file exists at `android/app/src/main/jniLibs/<abi>/libpdfium.so` for the ABI you’re running.
- If you’re running on an **emulator**, you almost certainly need `x86_64` (or restrict ABIs to arm and use an ARM emulator image).
- If you’re building split APKs / an App Bundle, ensure every ABI you ship has the matching `libpdfium.so`.

### `dlopen failed: library "libc++_shared.so" not found`

Some prebuilt PDFium builds may depend on the NDK C++ shared runtime.

Fix options:

- Prefer a PDFium build that links C++ statically (no `libc++_shared.so` dependency), or
- Add `libc++_shared.so` to the same `jniLibs/<abi>/` directories (copy it from your Android NDK), matching ABIs.

### Library exists but still won’t load

Rare, but if `libpdfium.so` is packaged yet still not discoverable via `dlopen()`:

- Ensure the library file permissions are sane: `chmod 644 android/app/src/main/jniLibs/*/libpdfium.so`
- Consider enabling legacy JNI lib packaging (forces extraction on install):
  - `android { packagingOptions { jniLibs { useLegacyPackaging true } } }`
  - or `android:extractNativeLibs="true"` in the `<application>` tag

Only apply these if you’ve confirmed the `.so` is present but still failing to load.

## References

- `pdfium-render` docs: https://docs.rs/pdfium-render
- `pdfium-binaries` releases: https://github.com/bblanchon/pdfium-binaries/releases
- Official PDFium repo: https://pdfium.googlesource.com/pdfium/
