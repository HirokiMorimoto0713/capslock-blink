# capslock-blink

Claude Code（や任意の CLI）が応答を終えて入力待ちになると、手元の Mac の **CapsLock 緑 LED をぴかぴか点滅**させます。次のプロンプトを打ち込むと消灯します。ターミナルから目を離していても、「そろそろ返事が来たな」が物理的に分かる、というだけの小さな道具です。

キーボードバックライト（キーの白色照明）ではなく **CapsLock LED** を使うのがポイントです。バックライトは環境光センサーの管理下にあって「部屋が明るいから」と勝手に消されますが、CapsLock LED はその管理外なので、明るい部屋でも確実に光ります。

## 仕組み

```
[母艦 = Claude Code が動くマシン]            [Mac]
  応答完了(Stop hook)  → touch flag
  送信(UserPromptSubmit) → rm flag
            │ SSH で監視                      poll.sh ──→ /tmp/claude-blink-state (on/off)
            └───────────────────────────────────────────────┘         │
                                                             capsled ──┘ CapsLock LED を点滅/消灯
```

- **母艦側**: CLI の hook で、応答完了時にフラグファイルを作り、送信時に消すだけ。
- **Mac 側（launchd 常駐）**:
  - `poll.sh` … SSH（ControlMaster で接続再利用）で母艦のフラグを 1 秒ごとに確認し、ローカルの状態ファイルに `on`/`off` を書く。
  - `capsled` … 状態ファイルを読んで IOKit HID API で CapsLock LED を 400ms ごとにトグル。

母艦→Mac ではなく **Mac→母艦の一方向 SSH** で見に行く設計なので、母艦側にグローバル IP や受信ポートは不要です。

## 母艦側のセットアップ

Claude Code の場合、`~/.claude/settings.json` の `hooks` に以下を追加します（他の CLI でも、応答完了・入力送信のフックがあれば同じ発想で組めます）。

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "touch ~/.claude/blink-flag || true" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "rm -f ~/.claude/blink-flag || true" } ] }
    ]
  }
}
```

これだけです。応答が終わるとフラグが立ち、次に何か送信すると消えます。

## Mac 側のセットアップ

前提: 母艦へ `ssh user@host` が **鍵認証で** 入れること／Xcode Command Line Tools（`swiftc`）が入っていること。

```bash
git clone https://github.com/HirokiMorimoto0713/capslock-blink.git
cd capslock-blink

# 設定を用意して母艦の SSH 先を書く
cp config.example ~/.capslock-blink/config
$EDITOR ~/.capslock-blink/config     # MOTHERSHIP="user@host" を自分の環境に

bash install-mac.sh
```

インストールが終わったら、**手動で 1 つだけ**権限を付けます（後述の「入力監視」の理由を参照）。

1. システム設定 → プライバシーとセキュリティ → **入力監視**
2. `＋` を押し、`~/.capslock-blink/capsled` を追加してチェックをオン
   （隠しフォルダが見えない時は選択ダイアログで `Cmd+Shift+.`）
3. 反映: `launchctl kickstart -k gui/$(id -u)/dev.capslock-blink.led`

## 動作確認

母艦側を介さず、Mac ローカルだけで LED を試せます。

```bash
echo on > /tmp/claude-blink-state    # 点滅するはず
sleep 3
echo off > /tmp/claude-blink-state   # 消える
```

これで光れば Mac 側は完成です。あとは母艦で CLI を動かせば、応答完了ごとに点滅します。

## トラブルシュート

**LED が光らない（ターミナルからの手動実行だと光るのに launchd だと光らない）**
入力監視の権限が launchd プロセスに効いていません。macOS の TCC は「入力監視」を実行バイナリごとに管理し、ターミナルの子プロセスと launchd 常駐プロセスは別扱いです。`~/.capslock-blink/capsled` を入力監視に追加してチェックをオンにし、`launchctl kickstart -k gui/$(id -u)/dev.capslock-blink.led` で入れ直してください。旧来の `launchctl load` ではなく **`launchctl bootstrap gui/$(id -u)`** で登録するのも、TCC のドメインを合わせるうえで重要です（install-mac.sh はこれを使っています）。

**ずっと点滅しっぱなし / 消えない**
`cat /tmp/claude-blink-state` と母艦側の `ls ~/.claude/blink-flag` を突き合わせます。SSH が切れていると poll が更新できません → `tail /tmp/capsled-poll.err.log`。

**常駐確認・再起動**

```bash
launchctl list | grep capslock-blink
launchctl kickstart -k gui/$(id -u)/dev.capslock-blink.led
launchctl kickstart -k gui/$(id -u)/dev.capslock-blink.poll
```

**止めたい**

```bash
launchctl bootout gui/$(id -u)/dev.capslock-blink.led
launchctl bootout gui/$(id -u)/dev.capslock-blink.poll
```

## 調整

- 点滅の速さ: `src/capsled.swift` の `0.4`（秒）を変更して `swiftc` で再ビルド。
- 監視間隔: `~/.capslock-blink/config` の `INTERVAL`。

## ライセンス

MIT
