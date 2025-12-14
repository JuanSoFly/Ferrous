#!/usr/bin/env bash


#   source ./setup_env.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script is meant to be sourced (it won't persist env vars if executed)."
  echo "Run: source ./setup_env.sh"
  exit 0
fi

path_prepend() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}

export PROJECT_ROOT
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

export RUSTUP_HOME="$PROJECT_ROOT/tools/rustup"
export CARGO_HOME="$PROJECT_ROOT/tools/cargo"

path_prepend "$CARGO_HOME/bin"
path_prepend "$PROJECT_ROOT/tools/flutter/bin"

# Android SDK (standard location).
if [[ -z "${ANDROID_HOME-}" && -d "$HOME/Android/Sdk" ]]; then
  export ANDROID_HOME="$HOME/Android/Sdk"
fi
if [[ -z "${ANDROID_SDK_ROOT-}" && -n "${ANDROID_HOME-}" ]]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
fi

if [[ -n "${ANDROID_HOME-}" ]]; then
  path_prepend "$ANDROID_HOME/cmdline-tools/latest/bin"
  path_prepend "$ANDROID_HOME/platform-tools"
fi

if [[ "${READERAPP_ENV_SILENT-}" != "1" ]]; then
  echo "Environment loaded."
  command -v rustc >/dev/null 2>&1 && echo "  rustc: $(command -v rustc)" || echo "  rustc: (not found)"
  command -v flutter >/dev/null 2>&1 && echo "  flutter: $(command -v flutter)" || echo "  flutter: (not found)"
  command -v sdkmanager >/dev/null 2>&1 && echo "  sdkmanager: $(command -v sdkmanager)" || echo "  sdkmanager: (not found)"
  command -v adb >/dev/null 2>&1 && echo "  adb: $(command -v adb)" || echo "  adb: (not found)"
fi
