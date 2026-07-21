#!/bin/bash
# Mac 側で一度だけ実行する。capsled をコンパイルし、launchd に常駐登録する。
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/.capslock-blink"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"
mkdir -p "$DIR" "$LA"

cp "$SRC/src/capsled.swift" "$SRC/src/poll.sh" "$DIR/"
chmod +x "$DIR/poll.sh"

# 設定ファイルが無ければ雛形をコピー
if [ ! -f "$DIR/config" ]; then
    cp "$SRC/config.example" "$DIR/config"
    echo "⚠  $DIR/config を作成しました。MOTHERSHIP を自分の母艦に書き換えてから続けてください。"
fi

# 素の CLI バイナリだと TCC（入力監視）が許可ダイアログを出してもリストに登録できないため、
# Info.plist 付きの最小 .app バンドルとしてビルドする
APP="$DIR/capsled.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.capslock-blink.capsled</string>
  <key>CFBundleName</key><string>capsled</string>
  <key>CFBundleExecutable</key><string>capsled</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "swiftc でコンパイル中..."
swiftc "$DIR/capsled.swift" -o "$APP/Contents/MacOS/capsled"
codesign --force --sign - "$APP"
rm -f "$DIR/capsled"   # 旧形式の素のバイナリが残っていたら片付ける

# plist を配置（__DIR__ を実パスに置換）
for name in led poll; do
    sed "s|__DIR__|$DIR|g" "$SRC/launchagents/dev.capslock-blink.$name.plist" \
        > "$LA/dev.capslock-blink.$name.plist"
done

# gui ドメインで bootstrap（TCC/入力監視の許可を正しく効かせるため load ではなく bootstrap を使う）
for label in led poll; do
    launchctl bootout "gui/$UID_NUM/dev.capslock-blink.$label" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$LA/dev.capslock-blink.$label.plist"
done

echo ""
echo "=== 完了 ==="
echo "まもなく『\"capsled\" で任意のアプリケーションからキー操作を受け取ろうとしています』の"
echo "ダイアログが出ます。「\"システム設定\"を開く」→ 入力監視リストの capsled をオンにして、"
echo "  launchctl kickstart -k gui/$UID_NUM/dev.capslock-blink.led"
echo "で反映してください。ダイアログを見逃したら上の kickstart でもう一度出せます。"
echo ""
launchctl list | grep capslock-blink || true
