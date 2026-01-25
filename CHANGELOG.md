# Changelog

## [1.0.0] - 2025-01-25

### ✨ Highlights

- **In-App Updates**: The app now checks for new versions automatically on startup
- **Automated Releases**: GitHub Actions now builds and publishes per-ABI APKs

### 🚀 New Features

- In-app update checker via GitHub Releases API
- Update dialog with version comparison and one-tap download
- Auto-detects correct APK for your device architecture

### ⚡ Improvements

- Added sccache for faster Rust compilation in CI
- Enabled per-ABI APK builds (arm64-v8a, armeabi-v7a, x86_64)

### 🐛 Bug Fixes

- Fixed cargokit script permissions in GitHub Actions
- Fixed release creation permissions

---