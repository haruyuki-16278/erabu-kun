#!/bin/bash
set -e

APP_NAME="Erabu-kun"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DMG_FILE="${BUILD_DIR}/${APP_NAME}.dmg"

# Developer ID 証明書の名前（キーチェーンにあるものと完全に一致させる）
DEVELOPER_ID="Developer ID Application: Toshiyuki Yamaji (3N2Q57WT95)"
TEAM_ID="3N2Q57WT95"

# ==========================================
# 0. .env の読み込みと認証情報のチェック
# ==========================================
if [ -f .env ]; then
    while IFS='=' read -r key value; do
        if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            export "$key=$value"
        fi
    done < <(grep -v '^#' .env | grep '=')
fi

# APPLE_ID または APP_SPECIFIC_PASSWORD が空の場合の対応
if [ -z "$APPLE_ID" ] || [ -z "$APP_SPECIFIC_PASSWORD" ]; then
    echo "❌ エラー: .env に APPLE_ID または APP_SPECIFIC_PASSWORD が設定されていません。"
    echo ""
    echo "【 .env ファイルの書き方 】"
    echo "APPLE_ID=your.apple.id@example.com"
    echo "APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx"
    echo ""
    
    # 既存の .env がパスワードだけの行になっている場合の警告
    if [ -f .env ]; then
        FIRST_LINE=$(head -n 1 .env || true)
        if [[ "$FIRST_LINE" != *"="* ]] && [ -n "$FIRST_LINE" ]; then
            echo "⚠️ 既存の .env は「$FIRST_LINE」のように値のみが記載されている可能性があります。"
            echo "上記のように KEY=VALUE の形式に修正してから再度実行してください。"
        fi
    fi
    exit 1
fi

echo "=== 1. クリーンビルド ==="
echo "Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}"
mkdir -p "${MAC_OS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp src/Info.plist "${CONTENTS_DIR}/Info.plist"

# ビルド番号は git のコミット数から自動生成する（コミットのたびに一意な連番になる）
BUILD_NUMBER=$(git rev-list --count HEAD)
echo "ビルド番号: ${BUILD_NUMBER} (git commit count)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

# アプリアイコン (icon.png) から .icns を生成して組み込む
if [ -f "icon.png" ]; then
    echo "Creating AppIcon.icns from icon.png..."
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"
    
    # 必要な各解像度のアイコンを生成
    sips -z 16 16     icon.png --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -z 32 32     icon.png --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     icon.png --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -z 64 64     icon.png --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   icon.png --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -z 256 256   icon.png --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   icon.png --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -z 512 512   icon.png --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   icon.png --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -z 1024 1024 icon.png --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null
    
    # .icnsファイルに変換してResourcesに配置
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    # Info.plist は Xcode プロジェクト（Asset Catalog経由でアイコンを解決）と共用しているため、
    # ここでは本スクリプト独自の .icns 埋め込み方式向けに CFBundleIconFile を後付けする。
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || true
else
    echo "⚠️ icon.png が見つかりませんでした。デフォルトのアイコンになります。"
fi

# メニューバー用アイコンのコピー
if [ -f "bar-icon.png" ]; then
    echo "Copying bar-icon.png to Resources..."
    cp bar-icon.png "${RESOURCES_DIR}/bar-icon.png"
fi

if [ -d "src/en.lproj" ]; then
    cp -r src/en.lproj "${RESOURCES_DIR}/"
fi
if [ -d "src/ja.lproj" ]; then
    cp -r src/ja.lproj "${RESOURCES_DIR}/"
fi

echo "Compiling Swift files..."
swiftc src/*.swift \
    -o "${MAC_OS_DIR}/${APP_NAME}" \
    -target x86_64-apple-macosx13.0 \
    -target arm64-apple-macosx13.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation

echo "Build complete: ${APP_DIR}"

echo "=== 2. コード署名 (Code Signing) ==="
echo "Signing app with: ${DEVELOPER_ID}"
# --deep: 内部のリソースやフレームワークにも再帰的に署名
# --force: 既存の署名を上書き
# --options runtime: Hardened Runtime を有効化（公証に必須）
# --entitlements: App Sandbox を有効化（Mac App Store 対応 / セキュリティスコープブックマーク利用に必須）
codesign --force --options runtime --deep --entitlements "src/Erabukun.entitlements" --sign "${DEVELOPER_ID}" "${APP_DIR}"

echo "=== 3. 配布用DMGの作成 (スタイリング付き) ==="
DMG_SRC_DIR="${BUILD_DIR}/dmg_source"
TEMP_DMG="${BUILD_DIR}/pack.temp.dmg"

rm -rf "${DMG_SRC_DIR}"
mkdir -p "${DMG_SRC_DIR}"
cp -R "${APP_DIR}" "${DMG_SRC_DIR}/"
ln -s /Applications "${DMG_SRC_DIR}/Applications"

echo "DMG用の背景画像を生成します..."
if swift gen_dmg_bg.swift; then
    mkdir -p "${DMG_SRC_DIR}/.background"
    cp dmg-background.png "${DMG_SRC_DIR}/.background/background.png"
else
    echo "⚠️ 背景画像の生成に失敗しました。デフォルト表示で続行します。"
fi

rm -f "${DMG_FILE}"
rm -f "${TEMP_DMG}"

echo "Read-Write 用のテンポラリDMGを作成しています..."
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_SRC_DIR}" -ov -fs HFS+ -format UDRW "${TEMP_DMG}" > /dev/null

echo "DMGをマウントして見た目を設定しています..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}" | egrep '^/dev/' | sed 1q | awk '{print $1}')

# Finderが認識するまで少し待つ
sleep 2

# AppleScript でウィンドウサイズとアイコン位置を調整 (Fit-Content 風)
echo '
   tell application "Finder"
     tell disk "'"${APP_NAME}"'"
           open
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           -- ウィンドウサイズをアプリとApplicationsが横に並ぶちょうどのサイズに (X, Y, Width, Height)
           set bounds of container window to {400, 100, 880, 360}
           set viewOptions to the icon view options of container window
           set arrangement of viewOptions to not arranged
           set icon size of viewOptions to 112
           
           try
               set background picture of viewOptions to file ".background:background.png"
           end try
           
           set position of item "'"${APP_NAME}"'.app" of container window to {120, 110}
           set position of item "Applications" of container window to {360, 110}
           close
           open
           update without registering applications
           delay 2
           close
     end tell
   end tell
' | osascript

echo "DMGをアンマウントしています..."
hdiutil detach "${DEVICE}" -force > /dev/null || true
sleep 1

echo "配布用の Read-Only 圧縮形式に変換しています..."
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_FILE}" > /dev/null
rm -f "${TEMP_DMG}"

echo "DMG化完了: ${DMG_FILE}"

echo "=== 4. 公証 (Notarization) の提出 ==="
echo "Apple へアップロードしています..."
# notarytool に提出し、出力を変数に格納する（標準エラーも標準出力にマージ）
set +e
SUBMIT_OUTPUT=$(xcrun notarytool submit "${DMG_FILE}" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" 2>&1)
SUBMIT_EXIT_CODE=$?
set -e

echo "$SUBMIT_OUTPUT"

if [ $SUBMIT_EXIT_CODE -ne 0 ]; then
    echo "❌ 提出に失敗しました。"
    exit 1
fi

# Submission ID を抽出: "id: 04edc0b1-xxxx-xxxx-xxxx-xxxx" のような形式
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE "id: [0-9a-f\-]+" | awk '{print $2}' | head -n 1 | tr -d '\r')

if [ -z "$SUBMISSION_ID" ]; then
    echo "❌ 提出成功しましたが、Submission ID を出力から取得できませんでした。"
    exit 1
fi

echo "Submission ID の取得成功: ${SUBMISSION_ID}"

echo "=== 5. 公証ステータスの確認 (約1分ごとのポーリング) ==="

while true; do
    echo "⏳ 1分待機してからステータスを確認します..."
    sleep 60
    
    echo "ステータスを確認中..."
    set +e
    INFO_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" 2>&1)
    set -e
    
    STATUS=$(echo "$INFO_OUTPUT" | awk -F': ' '/[sS]tatus:/ {print $2}' | tr -d ' ' | tr -d '\r')
    
    if [ -z "$STATUS" ]; then
        echo "➡️ ステータス取得エラーまたは処理中 (INFO出力: $INFO_OUTPUT)"
        continue
    fi
    
    echo "現在のステータス: $STATUS"
    
    if [ "$STATUS" = "Accepted" ]; then
        echo "✅ 公証が完了しました (Accepted)！"
        break
    elif [ "$STATUS" = "Invalid" ] || [ "$STATUS" = "Rejected" ]; then
        echo "❌ 公証が拒否されました ($STATUS)。"
        echo "エラーログを取得します:"
        xcrun notarytool log "$SUBMISSION_ID" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID"
        exit 1
    elif [ "$STATUS" = "InProgress" ]; then
        echo "➡️ まだ公証処理中です...(In Progress)"
    else
        echo "➡️ ステータス確認中... (表示: $STATUS)"
    fi
done

echo "=== 6. 公証のステープル (Staple) ==="
echo "DMGに公証チケットを添付します..."
xcrun stapler staple "${DMG_FILE}"

# DMG の場合は再作成不要なためステープルして完了
echo "🎉 すべてのプロセスが完了しました！"
echo "配布用パッケージ: ${DMG_FILE}"
