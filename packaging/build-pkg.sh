#!/bin/bash
#
# Builds the one installable artifact: OpenSuperWhisper-<version>.pkg
#
# The package contains the app bundle and a double-clickable uninstall command.
# It writes nothing into the user's home directory: the app's own state (dictation
# history, whisper models, transform weights) belongs to the app and is created on
# first launch, which is what makes "uninstall" a single, complete operation.
#
# Stock tools only: pkgbuild, productbuild, pkgutil. Signing and notarization
# happen when an identity/profile is supplied, and are skipped otherwise so the
# package can be built and inspected anywhere.
#
# Usage:
#   packaging/build-pkg.sh [--version <ver>] [--app <path>] [--out <path>]
#                          [--sign <installer identity>] [--notarize <profile>]
#
# Defaults:
#   --version   MARKETING_VERSION from OpenSuperWhisper.xcodeproj/project.pbxproj
#   --app       build/Build/Products/Release/OpenSuperWhisper.app
#   --out       OpenSuperWhisper-<version>.pkg
#
# Environment:
#   OSW_SIGN_IDENTITY    same as --sign
#   OSW_NOTARY_PROFILE   same as --notarize

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=""
APP_PATH="build/Build/Products/Release/OpenSuperWhisper.app"
OUT_PATH=""
SIGN_IDENTITY="${OSW_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${OSW_NOTARY_PROFILE:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)  VERSION="$2"; shift 2 ;;
        --app)      APP_PATH="$2"; shift 2 ;;
        --out)      OUT_PATH="$2"; shift 2 ;;
        --sign)     SIGN_IDENTITY="$2"; shift 2 ;;
        --notarize) NOTARY_PROFILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "build-pkg.sh: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION="$(grep -o 'MARKETING_VERSION = [^;]*' OpenSuperWhisper.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //')"
fi
[[ -n "$VERSION" ]] || { echo "build-pkg.sh: could not determine the version" >&2; exit 1; }
[[ -n "$OUT_PATH" ]] || OUT_PATH="OpenSuperWhisper-${VERSION}.pkg"

if [[ ! -d "$APP_PATH" ]]; then
    echo "build-pkg.sh: no app at $APP_PATH" >&2
    echo "  Build one first: ./notarize_app.sh <signing identity>   (or ./run.sh build for a local one)" >&2
    exit 1
fi

APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$APP_BUNDLE_ID" != "ru.starmel.OpenSuperWhisper" ]]; then
    echo "build-pkg.sh: $APP_PATH has bundle id '${APP_BUNDLE_ID:-<none>}', expected ru.starmel.OpenSuperWhisper" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/osw-pkg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

PAYLOAD_DIR="$WORK_DIR/payload"
RESOURCES_DIR="$WORK_DIR/resources"
COMPONENT_PKG="$WORK_DIR/OpenSuperWhisper-component.pkg"
mkdir -p "$PAYLOAD_DIR/Applications" "$RESOURCES_DIR"

echo "==> App signature"
# The Accessibility/Microphone grants follow the Designated Requirement. An
# ad-hoc (linker-only) signature has a cdhash-based DR, so every rebuild looks
# like a different app to TCC and the grant silently stops matching. Show what
# is in the package, and refuse to call an ad-hoc build distributable.
if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    codesign -d -r- "$APP_PATH" 2>&1 | sed 's/^/    /'
    if codesign -d -r- "$APP_PATH" 2>&1 | grep -q "cdhash"; then
        echo "    NOTE: this app is ad-hoc signed (cdhash requirement): rebuild with a real" >&2
        echo "          identity (OSW_APP_IDENTITY / notarize_app.sh) before shipping it." >&2
    fi
else
    echo "    WARNING: $APP_PATH does not verify (codesign --verify --deep --strict)." >&2
    echo "             The package will carry that signature unchanged." >&2
fi

echo "==> Payload"
# ditto preserves the bundle's extended attributes and its code signature.
ditto "$APP_PATH" "$PAYLOAD_DIR/Applications/OpenSuperWhisper.app"
install -m 755 "packaging/uninstall.sh" "$PAYLOAD_DIR/Applications/Uninstall OpenSuperWhisper.command"
# No extended attributes on the payload: pkgbuild would otherwise record an
# AppleDouble "._Uninstall OpenSuperWhisper.command" alongside it.
xattr -c "$PAYLOAD_DIR/Applications/Uninstall OpenSuperWhisper.command" 2>/dev/null || true

echo "==> Component package"
pkgbuild \
    --root "$PAYLOAD_DIR" \
    --identifier "ru.starmel.OpenSuperWhisper" \
    --version "$VERSION" \
    --install-location "/" \
    --scripts "packaging/scripts" \
    "$COMPONENT_PKG"

echo "==> Distribution"
sed "s/@@VERSION@@/$VERSION/g" packaging/distribution.xml > "$RESOURCES_DIR/distribution.xml"
cp packaging/conclusion.html "$RESOURCES_DIR/conclusion.html"

PRODUCTBUILD_ARGS=(
    --distribution "$RESOURCES_DIR/distribution.xml"
    --resources "$RESOURCES_DIR"
    --package-path "$WORK_DIR"
)
if [[ -n "$SIGN_IDENTITY" ]]; then
    PRODUCTBUILD_ARGS+=(--sign "$SIGN_IDENTITY")
fi
rm -f "$OUT_PATH"
productbuild "${PRODUCTBUILD_ARGS[@]}" "$OUT_PATH"

echo "==> Built $OUT_PATH"
/usr/sbin/pkgutil --check-signature "$OUT_PATH" || true

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Notarizing with profile $NOTARY_PROFILE"
    xcrun notarytool submit "$OUT_PATH" --wait --keychain-profile "$NOTARY_PROFILE"
    xcrun stapler staple "$OUT_PATH"
    xcrun stapler validate "$OUT_PATH"
else
    echo "==> Skipped notarization (no --notarize profile): the package is unsigned for distribution."
fi

echo ""
echo "Payload:"
/usr/sbin/pkgutil --payload-files "$OUT_PATH" | sed 's/^/  /'
echo ""
echo "Receipt id: ru.starmel.OpenSuperWhisper (this is what the uninstaller forgets)"
