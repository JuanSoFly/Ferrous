#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JNILIBS_DIR="${ROOT_DIR}/android/app/src/main/jniLibs"

# Comma or space-separated ABI list.
# Examples:
#   PDFIUM_ABIS="arm64-v8a,armeabi-v7a"
#   PDFIUM_ABIS="arm64-v8a x86_64"
PDFIUM_ABIS="${PDFIUM_ABIS:-arm64-v8a,armeabi-v7a}"

# Use "latest" (default) or a specific GitHub release tag.
# Note: tags with slashes (e.g. chromium/XXXX) are URL-encoded automatically.
PDFIUM_RELEASE="${PDFIUM_RELEASE:-latest}"

declare -rA ARCHIVE_FOR_ABI=(
  ["arm64-v8a"]="pdfium-android-arm64.tgz"
  ["armeabi-v7a"]="pdfium-android-arm.tgz"
  ["x86_64"]="pdfium-android-x64.tgz"
  ["x86"]="pdfium-android-x86.tgz"
)

print_usage() {
  cat <<'EOF'
Installs PDFium (libpdfium.so) into android/app/src/main/jniLibs/<abi>/.

Environment variables:
  PDFIUM_ABIS      Comma or space-separated ABIs.
                  Default: "arm64-v8a,armeabi-v7a"
                  Options: arm64-v8a, armeabi-v7a, x86_64, x86

  PDFIUM_RELEASE   GitHub release tag to pin to, or "latest" (default).
                  Tags containing "/" are URL-encoded automatically.

Examples:
  bash scripts/setup-pdfium-android.sh
  PDFIUM_ABIS="arm64-v8a,x86_64" bash scripts/setup-pdfium-android.sh
  PDFIUM_RELEASE="chromium/6411" bash scripts/setup-pdfium-android.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

release_escaped="${PDFIUM_RELEASE//\//%2F}"

download_url_for_archive() {
  local archive="$1"
  if [[ "${PDFIUM_RELEASE}" == "latest" ]]; then
    printf '%s' "https://github.com/bblanchon/pdfium-binaries/releases/latest/download/${archive}"
  else
    printf '%s' "https://github.com/bblanchon/pdfium-binaries/releases/download/${release_escaped}/${archive}"
  fi
}

split_abis() {
  local raw="$1"
  raw="${raw//,/ }"
  read -r -a abis <<<"${raw}"
  printf '%s\n' "${abis[@]}"
}

install_for_abi() {
  local abi="$1"
  local archive="${ARCHIVE_FOR_ABI[${abi}]:-}"
  if [[ -z "${archive}" ]]; then
    echo "error: unsupported ABI '${abi}'" >&2
    echo "supported: ${!ARCHIVE_FOR_ABI[*]}" >&2
    exit 2
  fi

  local url
  url="$(download_url_for_archive "${archive}")"

  (
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "${temp_dir}"' EXIT

    echo "==> ${abi}: downloading ${archive}"
    curl -fL -o "${temp_dir}/${archive}" "${url}"

    echo "==> ${abi}: extracting"
    tar -xzf "${temp_dir}/${archive}" -C "${temp_dir}"

    if [[ ! -f "${temp_dir}/lib/libpdfium.so" ]]; then
      echo "error: expected '${temp_dir}/lib/libpdfium.so' after extracting ${archive}" >&2
      exit 3
    fi

    mkdir -p "${JNILIBS_DIR}/${abi}"
    cp "${temp_dir}/lib/libpdfium.so" "${JNILIBS_DIR}/${abi}/libpdfium.so"

    echo "==> ${abi}: installed ${JNILIBS_DIR}/${abi}/libpdfium.so"
    ls -lh "${JNILIBS_DIR}/${abi}/libpdfium.so"
  )
}

echo "Installing PDFium into:"
echo "  ${JNILIBS_DIR}"
echo ""
echo "ABIs:"
split_abis "${PDFIUM_ABIS}" | sed 's/^/  - /'
echo ""

mkdir -p "${JNILIBS_DIR}"

while IFS= read -r abi; do
  [[ -z "${abi}" ]] && continue
  install_for_abi "${abi}"
done < <(split_abis "${PDFIUM_ABIS}")

echo ""
echo "Done."
