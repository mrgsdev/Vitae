#!/bin/sh
# Собирает Vitae в Release и упаковывает для релиза на GitHub. Приложите к релизу оба файла:
#   build/Vitae-<версия>.dmg — для людей: открыть и перетащить Vitae в «Программы»;
#   build/Vitae-<версия>.zip — для встроенного обновления. Читать подключённый образ macOS
#   разрешает только с согласия пользователя, поэтому обновление ставится из zip.
set -e
cd "$(dirname "$0")/.."

xcodebuild -project Vitae.xcodeproj -scheme Vitae -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build -quiet build

APP=build/Build/Products/Release/Vitae.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Vitae-$VERSION.dmg"
ZIP="build/Vitae-$VERSION.zip"
codesign --verify --deep --strict "$APP"

# Образ открывается с Vitae.app рядом со ссылкой на «Программы»: перетащите одно на другое.
# ditto сохраняет подпись.
STAGE=build/dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Vitae.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Vitae" -srcfolder "$STAGE" -format UDZO -ov -quiet "$DMG"
rm -rf "$STAGE"

# Снова ditto: обычный zip может повредить подпись.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Готово: $DMG и $ZIP — приложите к релизу оба"
echo "Тег релиза: v$VERSION"
