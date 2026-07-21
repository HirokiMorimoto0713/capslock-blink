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

echo "swiftc でコンパイル中..."
swiftc "$DIR/capsled.swift" -o "$DIR/capsled"

# 固定 identifier で ad-hoc 署名（TCC がバイナリを識別しやすくするため）
codesign --force --sign - --identifier dev.capslock-blink.capsled "$DIR/capsled" 2>/dev/null || true

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
echo "最後に手動で1つだけ:"
echo "  システム設定 → プライバシーとセキュリティ → 入力監視 に"
echo "  $DIR/capsled を追加してチェックをオンにしてください。"
echo "  （追加後） launchctl kickstart -k gui/$UID_NUM/dev.capslock-blink.led"
echo ""
launchctl list | grep capslock-blink || true
