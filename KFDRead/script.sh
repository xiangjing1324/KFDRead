#!/usr/bin/env bash
set -euo pipefail

if [[ "${PLATFORM_NAME:-}" != "iphoneos" && "${EFFECTIVE_PLATFORM_NAME:-}" != "-iphoneos" ]]; then
  echo "[tipa] Skip non-iphoneos build."
  exit 0
fi

: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
: "${CODESIGNING_FOLDER_PATH:?CODESIGNING_FOLDER_PATH is required}"
: "${SRCROOT:?SRCROOT is required}"
: "${PRODUCT_NAME:?PRODUCT_NAME is required}"

APP_DIR=""
if [[ -d "${TARGET_BUILD_DIR}/${CODESIGNING_FOLDER_PATH}" ]]; then
  APP_DIR="${TARGET_BUILD_DIR}/${CODESIGNING_FOLDER_PATH}"
elif [[ -d "${CODESIGNING_FOLDER_PATH}" ]]; then
  APP_DIR="${CODESIGNING_FOLDER_PATH}"
else
  echo "[tipa] App bundle not found." >&2
  exit 1
fi

INFO_PLIST="${APP_DIR}/Info.plist"
if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "[tipa] Missing Info.plist at ${INFO_PLIST}" >&2
  exit 1
fi

ENT_PATH=""
if [[ -n "${CODE_SIGN_ENTITLEMENTS:-}" && -f "${SRCROOT}/${CODE_SIGN_ENTITLEMENTS}" ]]; then
  ENT_PATH="${SRCROOT}/${CODE_SIGN_ENTITLEMENTS}"
elif [[ -f "${SRCROOT}/KFDRead/supports/Entitlements.plist" ]]; then
  ENT_PATH="${SRCROOT}/KFDRead/supports/Entitlements.plist"
elif [[ -f "${SRCROOT}/KFDRead/supports/entitlements.plist" ]]; then
  ENT_PATH="${SRCROOT}/KFDRead/supports/entitlements.plist"
elif [[ -f "${SRCROOT}/supports/Entitlements.plist" ]]; then
  ENT_PATH="${SRCROOT}/supports/Entitlements.plist"
elif [[ -f "${SRCROOT}/supports/entitlements.plist" ]]; then
  ENT_PATH="${SRCROOT}/supports/entitlements.plist"
else
  echo "[tipa] Entitlements file not found." >&2
  exit 2
fi

LDID_BIN="$(command -v ldid || true)"
if [[ -z "${LDID_BIN}" && -x "/opt/homebrew/bin/ldid" ]]; then
  LDID_BIN="/opt/homebrew/bin/ldid"
fi
if [[ -z "${LDID_BIN}" ]]; then
  echo "[tipa] ldid not found. Install ldid first." >&2
  exit 3
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null || true)"
BUILD_NO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}" 2>/dev/null || true)"
if [[ -z "${VERSION}" ]]; then VERSION="0.0.0"; fi
if [[ -z "${BUILD_NO}" ]]; then BUILD_NO="0"; fi

echo "[tipa] App: ${APP_DIR}"
echo "[tipa] Entitlements: ${ENT_PATH}"

/usr/bin/codesign --remove-signature "${APP_DIR}" >/dev/null 2>&1 || true

EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${INFO_PLIST}" 2>/dev/null || true)"
if [[ -z "${EXEC_NAME}" ]]; then
  EXEC_NAME="${PRODUCT_NAME}"
fi
MAIN_BIN="${APP_DIR}/${EXEC_NAME}"
if [[ ! -f "${MAIN_BIN}" ]]; then
  echo "[tipa] Main executable not found: ${MAIN_BIN}" >&2
  exit 4
fi

sign_if_macho() {
  local file_path="$1"
  if [[ ! -f "${file_path}" ]]; then
    return 0
  fi
  if /usr/bin/file "${file_path}" 2>/dev/null | /usr/bin/grep -q "Mach-O"; then
    "${LDID_BIN}" -S"${ENT_PATH}" "${file_path}"
  fi
}

sign_if_macho "${MAIN_BIN}"

while IFS= read -r -d '' bin; do
  sign_if_macho "${bin}" || true
done < <(find "${APP_DIR}" -type f \( -name "*.dylib" -o -path "*/Frameworks/*.framework/*" \) -print0 2>/dev/null || true)

OUT_DIR="${SRCROOT}/packages"
OUT_NAME="${PRODUCT_NAME}_${VERSION}_${BUILD_NO}.tipa"
OUT_PATH="${OUT_DIR}/${OUT_NAME}"
WORK_DIR="${TARGET_BUILD_DIR}/tipa_payload_tmp"

rm -rf "${WORK_DIR}" "${OUT_PATH}"
mkdir -p "${WORK_DIR}/Payload" "${OUT_DIR}"
cp -R "${APP_DIR}" "${WORK_DIR}/Payload/"

(
  cd "${WORK_DIR}"
  /usr/bin/zip -qry "${OUT_PATH}" Payload
)

rm -rf "${WORK_DIR}"
echo "[tipa] Created: ${OUT_PATH}"
