#!/bin/bash
# Builds the disk image macOS opens without a word about unverified developers.
#
# The dialog people see on a downloaded build is not a signing problem alone -
# an ad hoc or even a Developer ID signature still raises it. What removes it is
# notarisation: Apple scans the upload, issues a ticket, and `stapler` writes
# that ticket into the file so the check also passes on a machine that is
# offline the first time the app runs.
#
# Both the app and the image are notarised. The image is what gets downloaded,
# but the app is what survives being dragged out of it onto another Mac, and a
# ticket stapled only to the image does not travel with the copy.
#
# One-time setup:
#   1. Apple Developer Program membership (the free Apple ID tier cannot issue
#      a Developer ID certificate, only an Apple Development one, which is not
#      valid for distribution).
#   2. In Xcode or on developer.apple.com, create a "Developer ID Application"
#      certificate and let it land in the login keychain.
#   3. An app-specific password from appleid.apple.com, then:
#        xcrun notarytool store-credentials gootd \
#            --apple-id you@example.com --team-id XXXXXXXXXX --password abcd-efgh-ijkl-mnop
#
# Overrides: GOOTD_SIGN_ID, GOOTD_NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Gootd.app"
DMG="build/Gootd.dmg"
ZIP="build/Gootd-submission.zip"
PROFILE="${GOOTD_NOTARY_PROFILE:-gootd}"

SIGN_ID="${GOOTD_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)}"

if [ -z "$SIGN_ID" ]; then
    cat >&2 <<'MSG'
no "Developer ID Application" certificate in the keychain.

  `security find-identity -v -p codesigning` lists what is there. An
  "Apple Development" certificate is not a substitute - it signs builds for
  your own registered machines, not for distribution, and cannot be notarised.

  Xcode > Settings > Accounts > Manage Certificates > + > Developer ID
  Application, with a paid Apple Developer Program account selected.
MSG
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MSG
no notarytool credentials stored under the profile "$PROFILE".

  xcrun notarytool store-credentials $PROFILE \\
      --apple-id <your apple id> --team-id <your team id> --password <app-specific password>

  The team id is the code in brackets in \`security find-identity -v\`.
  The password comes from appleid.apple.com > Sign-In and Security >
  App-Specific Passwords - your Apple ID password itself will not work.
MSG
    exit 1
fi

export GOOTD_SIGN_ID="$SIGN_ID"

# notarytool exits 0 even when Apple rejects the upload, so the verdict has to
# be read out of the output rather than the exit status - otherwise a failed
# submission would sail through and ship a warning build.
notarise() {
    local target="$1" out id
    echo "· notarising $(basename "$target") - this waits on Apple, usually a minute or two"
    out=$(xcrun notarytool submit "$target" --keychain-profile "$PROFILE" --wait 2>&1) || true
    echo "$out" | sed 's/^/    /'
    if ! grep -q "status: Accepted" <<<"$out"; then
        id=$(sed -n 's/^ *id: \([0-9a-fA-F-]\{36\}\).*/\1/p' <<<"$out" | head -1)
        echo >&2
        echo "notarisation was not accepted." >&2
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        exit 1
    fi
}

./build.sh

rm -f "$ZIP"
# ditto, not zip: the bundle's symlinks and metadata have to reach Apple intact.
ditto -c -k --keepParent "$APP" "$ZIP"
notarise "$ZIP"
rm -f "$ZIP"
xcrun stapler staple "$APP"

# Built after stapling, so the copy inside the image carries its own ticket.
./makedmg.sh
notarise "$DMG"
xcrun stapler staple "$DMG"

echo "· verifying"
codesign --verify --strict --verbose=1 "$APP"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
# What Gatekeeper itself will say. "accepted / Notarized Developer ID" on both
# lines is the whole point of this script.
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo
echo "  shippable  $(pwd)/$DMG  ($(du -h "$DMG" | cut -f1))"
echo "  copy it to ../landing/Gootd.dmg"
