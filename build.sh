#!/bin/bash
# 构建 WinKey.app —— 可直接拖入 /Applications 使用。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="WinKey"
BUNDLE_ID="com.local.winkey"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"

echo "==> 编译 (release)"
swift build -c release

echo "==> 组装 .app bundle"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# 图标：优先用 icns，没有就生成
# 图标：应用图标 (icns) + 菜单栏模板图标 (png)
#
# 应用图标以 Resources/WinKey-app.icns 为准 —— 这是设计定稿，
# 不要被脚本重新生成覆盖。若该文件不存在，才回退到 import_icon.py 生成。
if [ -f "Resources/WinKey-app.icns" ]; then
    cp "Resources/WinKey-app.icns" "${APP_DIR}/Contents/Resources/WinKey.icns"
    echo "    应用图标: WinKey-app.icns（设计定稿）"
elif [ -f "Resources/WinKey.icns" ]; then
    cp "Resources/WinKey.icns" "${APP_DIR}/Contents/Resources/WinKey.icns"
    echo "    应用图标: WinKey.icns"
else
    echo "==> 生成图标"
    python3 tools/import_icon.py 2>&1 | sed 's/^/    /' \
        || echo "    ⚠️  图标生成失败（需要 Pillow），跳过"
    [ -f "Resources/WinKey.icns" ] && cp "Resources/WinKey.icns" "${APP_DIR}/Contents/Resources/WinKey.icns"
fi
# 菜单栏图标必须进 bundle，否则状态栏会回退成系统键盘符号
for f in MenuBarIcon.png MenuBarIcon@2x.png; do
    if [ -f "Resources/$f" ]; then
        cp "Resources/$f" "${APP_DIR}/Contents/Resources/$f"
    fi
done
if [ -f "Resources/MenuBarIcon.png" ]; then
    echo "    菜单栏图标: MenuBarIcon.png / MenuBarIcon@2x.png"
else
    echo "    ⚠️  缺少菜单栏图标，状态栏将回退为系统符号"
fi

# 本地化资源：把 *.lproj 原样拷进 bundle，否则界面会显示文案 key
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    # 先校验格式：.strings 不支持 # 注释，写错会导致整个文件静默失效，
    # 界面全部退化成显示 key。这里提前拦住。
    if ! plutil -lint "${lproj}/Localizable.strings" >/dev/null 2>&1; then
        echo "    ❌ ${lproj}/Localizable.strings 格式错误："
        plutil -lint "${lproj}/Localizable.strings" 2>&1 | sed 's/^/       /'
        exit 1
    fi
    cp -R "$lproj" "${APP_DIR}/Contents/Resources/"
done
echo "    本地化文件已校验并打包"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>WinKey</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>WinKey</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- 纯菜单栏应用，不显示 Dock 图标 -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>WinKey ${VERSION}</string>
</dict>
</plist>
PLIST

echo "==> 签名"
# 优先使用本机自签证书：签名稳定，重建后不会让「辅助功能」授权失效。
# 这是关键——ad-hoc 签名每次编译 CDHash 都变，TCC 会把新包当成另一个应用，
# 用户就得反复重新授权。
SIGN_IDENTITY="WinKey Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "    使用自签证书: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" \
        --identifier "$BUNDLE_ID" \
        --options runtime \
        "${APP_DIR}" 2>&1 | sed 's/^/    /'
else
    echo "    ⚠️  未找到自签证书，回退 ad-hoc 签名（重建后需重新授权）"
    codesign --force --deep --sign - \
        --identifier "$BUNDLE_ID" \
        --options runtime \
        "${APP_DIR}" 2>&1 | sed 's/^/    /'
fi

echo "==> 校验签名"
codesign --verify --verbose=2 "${APP_DIR}" 2>&1 | sed 's/^/    /'

echo ""
echo "构建完成: $(pwd)/${APP_DIR}"
echo ""
echo "安装方式："
echo "  cp -R \"${APP_DIR}\" /Applications/"
echo "  然后在「系统设置 > 隐私与安全性 > 辅助功能」中勾选 WinKey"
