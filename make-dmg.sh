#!/bin/zsh
# Packages build/ExposeLabels.app into build/ExposeLabels.dmg with the drag-to-Applications layout.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
STAGE=build/dmg-stage; RW=build/rw.dmg; OUT=build/ExposeLabels.dmg; VOL="ExposeLabels"
rm -rf $STAGE $RW $OUT; mkdir -p $STAGE
cp -R build/ExposeLabels.app $STAGE/
ln -s /Applications $STAGE/Applications
hdiutil create -quiet -volname "$VOL" -srcfolder $STAGE -fs HFS+ -format UDRW -size 20m $RW
MNT=$(hdiutil attach -readwrite -noverify -noautoopen $RW | awk -F'\t' '/\/Volumes\//{print $NF}')
# Lay out the Finder window: app on the left, Applications on the right.
osascript <<OSA || echo "(layout step skipped — the DMG still works)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 200, 740, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set position of item "ExposeLabels.app" of container window to {140, 160}
    set position of item "Applications" of container window to {400, 160}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach -quiet "$MNT"
hdiutil convert -quiet $RW -format UDZO -imagekey zlib-level=9 -o $OUT
rm -rf $RW $STAGE
echo "Built $OUT"
