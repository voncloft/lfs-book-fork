#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local file=$1
  local needle=$2

  if ! grep -Fq "$needle" "$file"; then
    printf 'Assertion failed: expected to find %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

assert_not_matches() {
  local file=$1
  local pattern=$2

  if grep -Eq "$pattern" "$file"; then
    printf 'Assertion failed: did not expect %s to match %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

"$ROOT_DIR/generate-mlfs-ents.sh" fixture-version \
  --packages-html "$ROOT_DIR/tests/fixtures/packages-sample.html" \
  --patches-html "$ROOT_DIR/tests/fixtures/patches-sample.html" \
  --output-dir "$TMP_DIR" \
  --suffix test >/dev/null

PACKAGES_OUT="$TMP_DIR/packages-test.ent"
PATCHES_OUT="$TMP_DIR/patches-test.ent"

assert_contains "$PACKAGES_OUT" '<!ENTITY binutils-version "2.46.0">'
assert_contains "$PACKAGES_OUT" '<!ENTITY binutils-url "https://sourceware.org/pub/binutils/releases/binutils-2.46.0.tar.xz">'
assert_contains "$PACKAGES_OUT" '<!ENTITY expat-dl-version "2_7_4">'
assert_contains "$PACKAGES_OUT" '<!ENTITY linux-major-version "6">'
assert_contains "$PACKAGES_OUT" '<!ENTITY linux-minor-version "18">'
assert_contains "$PACKAGES_OUT" '<!ENTITY linux-patch-version "10">'
assert_contains "$PACKAGES_OUT" '<!ENTITY linux-majmin-version "6.18">'
assert_contains "$PACKAGES_OUT" '<!ENTITY python-minor "3.14">'
assert_contains "$PACKAGES_OUT" '<!ENTITY python-docs-url "https://www.python.org/ftp/python/doc/3.14.3/python-3.14.3-docs-html.tar.bz2">'
assert_contains "$PACKAGES_OUT" '<!ENTITY sqlite-short-version "3.51.2">'
assert_contains "$PACKAGES_OUT" '<!ENTITY sqlite-year "2026">'
assert_contains "$PACKAGES_OUT" '<!ENTITY systemd-man-version "259.1">'
assert_contains "$PACKAGES_OUT" '<!ENTITY tcl-major-version "8.6">'
assert_contains "$PACKAGES_OUT" '<!ENTITY util-linux-minor "2.41">'
assert_contains "$PACKAGES_OUT" '<!ENTITY vim-docdir "vim/vim92">'

assert_contains "$PATCHES_OUT" '<!ENTITY coreutils-i18n-patch "coreutils-9.10-i18n-1.patch">'
assert_contains "$PATCHES_OUT" '<!ENTITY coreutils-i18n-patch-size "128 KB">'
assert_contains "$PATCHES_OUT" '<!ENTITY kbd-backspace-patch "kbd-2.9.0-backspace-1.patch">'
assert_not_matches "$PATCHES_OUT" '^<!ENTITY openrc-lock-patch '

printf 'Tests passed.\n'
