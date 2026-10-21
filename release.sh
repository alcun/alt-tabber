#!/bin/zsh
# Build, sign with Developer ID, notarize, staple, publish to GitHub and bump the
# Homebrew cask. Needs: a Developer ID Application certificate, notarytool
# credentials (NOTARY_PROFILE, default "heyra": any profile for the same team works),
# gh logged in, and the tap checked out at ../homebrew-tap.
set -e
cd "$(dirname "$0")"
VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
PROFILE="${NOTARY_PROFILE:-heyra}"
TAPDIR=../homebrew-tap
TAP=$TAPDIR/Casks/alt-tabber.rb
[[ -z $(git status --porcelain) ]] || { echo "commit first"; exit 1; }

SIGN_ID="${SIGN_ID:-Developer ID Application}" ./build.sh --no-install
# Notarization needs a secure timestamp, which build.sh skips for speed.
codesign --force --options runtime --timestamp --sign "${SIGN_ID:-Developer ID Application}" build/AltTabber.app
OUT=$(mktemp -d)
ditto -c -k --keepParent build/AltTabber.app "$OUT/AltTabber.zip"
xcrun notarytool submit "$OUT/AltTabber.zip" --keychain-profile "$PROFILE" --wait | tee "$OUT/notary.txt"
grep -q "status: Accepted" "$OUT/notary.txt" || { echo "Apple didn't accept it; nothing published"; exit 1; }
xcrun stapler staple build/AltTabber.app
rm "$OUT/AltTabber.zip"
ditto -c -k --keepParent build/AltTabber.app "$OUT/AltTabber.zip"
spctl --assess --type execute -v build/AltTabber.app

[[ -n "$DRY_RUN" ]] && { echo "Dry run: notarized zip at $OUT/AltTabber.zip"; exit 0; }

git tag "v$VERSION"
git push origin main "v$VERSION"
# This version's section of CHANGELOG.md is the release notes.
awk -v v="## $VERSION" '$0 == v {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$OUT/notes.md"
gh release create "v$VERSION" "$OUT/AltTabber.zip" --title "alt-tabber $VERSION" --notes-file "$OUT/notes.md"

SHA=$(shasum -a 256 "$OUT/AltTabber.zip" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP"
git -C "$TAPDIR" add Casks/alt-tabber.rb README.md
git -C "$TAPDIR" commit -qm "alt-tabber $VERSION"
git -C "$TAPDIR" push -q
echo "Released $VERSION: brew upgrade --cask alt-tabber"
