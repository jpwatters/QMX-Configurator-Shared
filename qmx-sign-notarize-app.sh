#!/bin/bash
# Sign "QMX+ Configurator.app" with your Developer ID, have Apple notarize it,
# and staple the result, so it opens on any Mac without the "unidentified
# developer" warning (including copies downloaded from GitHub or in a zip).
#
#   ./qmx-sign-notarize-app.sh
#
# Run it again whenever launcher/qmx-launcher.c or anything inside the app
# (Contents/Resources/qmx-launcher.sh, the icon, Info.plist) changes: signing
# seals the app, and an edited app no longer matches its signature. Changes to
# the Python program itself do NOT need it: the app runs the program from
# ~/src/QMX-Configurator.
#
# One-time setup (see README):
#   1. Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. App-specific password from account.apple.com, then:
#        xcrun notarytool store-credentials QMX-notary --apple-id <you> --team-id <TEAMID>
# Options (environment variables):
#   SIGN_IDENTITY  "Developer ID Application: Name (TEAMID)"   (default: the first one found)
#   NOTARY_PROFILE keychain profile from store-credentials       (default: QMX-notary)
set -euo pipefail
cd "$(dirname "$0")"

APP="QMX+ Configurator.app"
SRC="launcher/qmx-launcher.c"
EXE="$APP/Contents/MacOS/qmx-launcher"
PROFILE="${NOTARY_PROFILE:-QMX-notary}"

step() { echo; echo "== $*"; }
die()  { echo; echo "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------- checks
[ -d "$APP" ] || die "$APP not found next to this script."
[ -f "$SRC" ] || die "$SRC not found."
xcode-select -p >/dev/null 2>&1 || die "Xcode or its command line tools are not installed (xcode-select --install)."

step "Finding your Developer ID Application certificate"
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)
fi
[ -n "$IDENTITY" ] || die "No \"Developer ID Application\" certificate in your keychain.
Create one: Xcode > Settings > Accounts > (your Apple ID) > Manage Certificates > + > Developer ID Application.
Check with: security find-identity -v -p codesigning"
echo "Using: $IDENTITY"

step "Checking the notarization credentials (profile \"$PROFILE\")"
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  die "No working notarytool profile called \"$PROFILE\".
Create an app-specific password at account.apple.com (Sign-In and Security > App-Specific Passwords), then run:
  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id <your Team ID>
(Team ID: developer.apple.com > Account > Membership details.)"
fi
echo "OK"

# ---------------------------------------------------------------- build
step "Building the launcher (Apple silicon + Intel)"
xcrun clang -O2 -Wall -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -o "$EXE" "$SRC"
echo "Built: $(lipo -archs "$EXE")"

# ---------------------------------------------------------------- sign
step "Signing"
find "$APP" -name .DS_Store -delete          # Finder files inside the app would break the seal
xattr -cr "$APP"                            # extended attributes (Finder info, quarantine) too
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# ---------------------------------------------------------------- notarize
step "Sending to Apple for notarization (usually a minute or two)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ditto -c -k --keepParent "$APP" "$TMP/launcher.zip"
RESULT=$(xcrun notarytool submit "$TMP/launcher.zip" --keychain-profile "$PROFILE" --wait --output-format json) || true
STATUS=$(printf '%s' "$RESULT" | sed -n 's/.*"status" *: *"\([^"]*\)".*/\1/p' | head -n 1)
ID=$(printf '%s' "$RESULT" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n 1)
STATUS=${STATUS:-unknown}
echo "Status: $STATUS"
if [ "$STATUS" != "Accepted" ]; then
  echo "$RESULT"
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || true
  die "Notarization was not accepted (see Apple's log above)."
fi

# ---------------------------------------------------------------- staple + check
step "Stapling Apple's ticket to the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

step "Gatekeeper check"
spctl --assess --type execute --verbose=2 "$APP"

echo
echo "Done: $APP is signed and notarized."
echo "Copy it to /Applications (replace the old one), and run ./push-to-github.sh to publish it."
