#!/usr/bin/env bash
#
# 加固版编译脚本（相对上游的改动）：
#   - 不再往登录钥匙串里导入自签名证书，改用 ad-hoc 签名（--sign -）。
#     代价：每次重新编译后，第一次读取 Claude 钥匙串凭证时 macOS 会再弹一次授权。
#     这其实是好事：二进制一变你就会被提醒。
#   - 不再打包 DMG。
#   - 开机自启（LaunchAgent）改为可选：加 --autostart 才安装。
#   - 只结束我们自己安装的那个进程，不再 pkill 所有名字带 usage-touchbar 的进程。
#
# 用法：
#   ./scripts/build-and-sign.sh               # 编译 + 签名 + 安装到 ~/Applications，并启动
#   ./scripts/build-and-sign.sh --autostart   # 同上，并设置登录时自动启动
#   ./scripts/build-and-sign.sh --uninstall   # 停止、移除 App 和自启项
#
set -euo pipefail

WANT_AUTOSTART=0
WANT_UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --autostart) WANT_AUTOSTART=1 ;;
        --uninstall) WANT_UNINSTALL=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

BUNDLE_ID="local.usage-touchbar"
LABEL="local.usage-touchbar"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/UsageTouchBar.app"
INSTALLED_BIN="$INSTALLED_APP/Contents/MacOS/usage-touchbar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
cd "$ROOT"

stop_running() {
    launchctl unload "$PLIST" 2>/dev/null || true
    pkill -f "^$INSTALLED_BIN" 2>/dev/null || true
}

if [[ "$WANT_UNINSTALL" == "1" ]]; then
    stop_running
    rm -f "$PLIST"
    rm -rf "$INSTALLED_APP"
    echo "✓ Uninstalled. (Config left at ~/.config/usage-touchbar — delete it if you like.)"
    exit 0
fi

# 1. 编译通用二进制（arm64 + x86_64）
echo "› Building universal release (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64

BINARY="$ROOT/.build/apple/Products/Release/usage-touchbar"
if [[ ! -f "$BINARY" ]]; then
    echo "Universal binary not found at $BINARY" >&2
    exit 1
fi
echo "  architectures: $(lipo -archs "$BINARY")"

# 2. 组装 App bundle
APP="$ROOT/UsageTouchBar.app"
echo "› Building app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BINARY" "$APP/Contents/MacOS/usage-touchbar"
cp -f "$ROOT/Info.plist" "$APP/Contents/Info.plist"
iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# 3. ad-hoc 签名（不碰任何钥匙串）
echo "› Ad-hoc signing…"
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign - "$APP/Contents/MacOS/usage-touchbar"
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign - "$APP"
codesign --verify --verbose "$APP" >/dev/null 2>&1 && echo "  signature OK."

# 4. 安装到 ~/Applications（用户目录，不需要管理员密码）
stop_running
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$APP" "$INSTALL_DIR/"

# 5. 可选：登录时自动启动
if [[ "$WANT_AUTOSTART" == "1" ]]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED_BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST_EOF
    launchctl load "$PLIST"
    echo "✓ Installed with autostart: $INSTALLED_APP"
else
    rm -f "$PLIST"
    open "$INSTALLED_APP"
    echo "✓ Installed and launched (no autostart): $INSTALLED_APP"
fi

echo "  首次读取 Claude 凭证时会弹钥匙串授权；每次重新编译后会再弹一次，属正常现象。"
