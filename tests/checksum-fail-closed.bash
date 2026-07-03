#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

RAW_SCRIPT="${TMP_DIR}/verify-raw.bash"
VERIFY_SCRIPT="${TMP_DIR}/verify.bash"
OUTPUT="${TMP_DIR}/output.txt"
FAKE_BIN="${TMP_DIR}/bin"
DOWNLOAD_DIR="${TMP_DIR}/download"
ASSET="asc_test_linux_amd64"

awk '
  /^    - name: Verify SHA-256 checksum$/ { in_step = 1; next }
  in_step && /^    - name: / { exit }
  in_step && /^      run: \|$/ { in_run = 1; next }
  in_run {
    sub(/^        /, "")
    print
  }
' "${ROOT}/action.yml" > "${RAW_SCRIPT}"

sed \
  -e 's#^DIR=.*#DIR="${DOWNLOAD_DIR}"#' \
  -e 's#^ASSET=.*#ASSET="${RESOLVED_ASSET}"#' \
  "${RAW_SCRIPT}" > "${VERIFY_SCRIPT}"

mkdir -p "${FAKE_BIN}" "${DOWNLOAD_DIR}"
for tool in grep awk tr; do
  ln -s "$(command -v "${tool}")" "${FAKE_BIN}/${tool}"
done

printf 'binary fixture\n' > "${DOWNLOAD_DIR}/${ASSET}"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "${ASSET}" > "${DOWNLOAD_DIR}/checksums.txt"

set +e
PATH="${FAKE_BIN}" DOWNLOAD_DIR="${DOWNLOAD_DIR}" RESOLVED_ASSET="${ASSET}" "${BASH_BIN}" "${VERIFY_SCRIPT}" > "${OUTPUT}" 2>&1
STATUS=$?
set -e

if [ "${STATUS}" -eq 0 ]; then
  echo "Expected checksum verification to fail when no SHA-256 tool is available"
  cat "${OUTPUT}"
  exit 1
fi

if ! grep -q "::error::No SHA-256 checksum tool available" "${OUTPUT}"; then
  echo "Expected a clear missing checksum tool error"
  cat "${OUTPUT}"
  exit 1
fi

if ! grep -q "Install shasum or sha256sum" "${OUTPUT}"; then
  echo "Expected installation guidance for shasum or sha256sum"
  cat "${OUTPUT}"
  exit 1
fi

if grep -q "Skipping verification" "${OUTPUT}"; then
  echo "Checksum verification must not be skipped"
  cat "${OUTPUT}"
  exit 1
fi

echo "checksum verification fails closed without SHA-256 tooling"
