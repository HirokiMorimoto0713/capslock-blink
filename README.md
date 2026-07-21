# capslock-blink

Claude Code（や任意の CLI）が応答を終えて入力待ちになったとき、あるいは途中でツール実行の許可や選択肢の回答を待っているときに、手元の Mac の **CapsLock 緑 LED をぴかぴか点滅**させます。次のプロンプトを打ち込む（または許可を出して作業が再開する）と消灯します。ターミナルから目を離していても、「そろそろ返事が来たな」が物理的に分かる、というだけの小さな道具です。

キーボードバックライト（キーの白色照明）ではなく **CapsLock LED** を使うのがポイントです。バックライトは環境光センサーの管理下にあって「部屋が明るいから」と勝手に消されますが、CapsLock LED はその管理外なので、明るい部屋でも確実に光ります。

## 構成は2種類

- **ローカル構成（デフォルト）**: Claude Code も CapsLock LED も同じ Mac 上で動かします。SSH 不要で、`poll.sh` がローカルの `~/.claude/blink-flag` を直接見ます。母艦を別途用意しない、いちばん手軽な構成です。
- **リモート構成**: 母艦（Linux など別マシン）で Claude Code を動かし、Mac が SSH でポーリングします。母艦とMacが別マシンのときはこちら。

`config` の `MOTHERSHIP` を `"local"`（デフォルト）にしておけばローカル構成、`user@host` を書けばリモート構成になります。hook の設定（flag の touch/rm）はどちらの構成でも共通です。

## 仕組み

### ローカル構成

```
[Mac]
  Claude Code の応答完了(Stop) / 許可・選択待ち(Notification) → touch ~/.claude/blink-flag
  送信(UserPromptSubmit) / ツール実行開始(PreToolUse) → rm ~/.claude/blink-flag
            │
            poll.sh ──→ /tmp/claude-blink-state (on/off)
                                                  │
                                        capsled ──┘ CapsLock LED を点滅/消灯
  CapsLock 2回押し → dismiss ファイル作成 → poll.sh が ~/.claude/blink-flag を rm
```

`poll.sh` が SSH を使わず、ローカルの flag ファイルの有無を直接 `test -f` で確認するだけです。

### リモート構成

```
[母艦 = Claude Code が動くマシン]            [Mac]
  応答完了(Stop) / 許可・選択待ち(Notification) → touch flag
  送信(UserPromptSubmit) / ツール実行開始(PreToolUse) → rm flag
            │ SSH で監視                      poll.sh ──→ /tmp/claude-blink-state (on/off)
            └───────────────────────────────────────────────┘         │
                                                             capsled ──┘ CapsLock LED を点滅/消灯
                                        CapsLock 2回押し → dismiss ファイル作成 → poll.sh が母艦の flag を rm
```

- **母艦側**: CLI の hook で、「ユーザーの入力を待ち始めたら」フラグファイルを作り、「入力が来て動き出したら」消すだけ。応答完了（`Stop`）だけでなく、ツール実行の許可待ちや質問の選択待ち（`Notification`）でも光ります。
- **Mac 側（launchd 常駐）**:
  - `poll.sh` … SSH（ControlMaster で接続再利用）で母艦のフラグを 1 秒ごとに確認し、ローカルの状態ファイルに `on`/`off` を書く。CapsLock 2回押しの dismiss ファイルがあれば、母艦の flag を `rm` してから `off` を書く。
  - `capsled` … 状態ファイルを読んで IOKit HID API で CapsLock LED を 400ms ごとにトグル。CapsLock 押下も監視していて、点滅中の2回押しを検知すると dismiss ファイルを作って即座に消灯する。

母艦→Mac ではなく **Mac→母艦の一方向 SSH** で見に行く設計なので、母艦側にグローバル IP や受信ポートは不要です。

## 母艦側のセットアップ

この hooks 設定はローカル構成・リモート構成の両方で共通です。ローカル構成の場合は「母艦」＝この Mac 自身なので、Mac 上の `~/.claude/settings.json` に同じものを書いてください。

Claude Code の場合、`~/.claude/settings.json` の `hooks` に以下を追加します（他の CLI でも、応答完了・入力送信のフックがあれば同じ発想で組めます）。

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "touch ~/.claude/blink-flag || true" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "touch ~/.claude/blink-flag || true" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "rm -f ~/.claude/blink-flag || true" } ] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "rm -f ~/.claude/blink-flag || true" } ] }
    ]
  }
}
```

4 つの hook の意味はこうです。

| hook | タイミング | 動作 |
|------|-----------|------|
| `Stop` | 応答が完了して入力待ちになった | 点滅開始 |
| `Notification` | ツール実行の許可待ち・質問の選択待ち・60秒アイドル | 点滅開始 |
| `UserPromptSubmit` | 次のプロンプトを送信した | 消灯 |
| `PreToolUse` | 許可が下りてツールが動き出した | 消灯 |

`Stop` / `UserPromptSubmit` の 2 つだけでも「応答完了→点滅」の基本は動きます。`Notification` / `PreToolUse` を足すと、応答の途中で許可や選択の回答を待って止まっているときにも光るようになります（`Notification` は 60 秒アイドルでも発火するので、放置していると勝手に光り出す挙動も付いてきます）。`PreToolUse` の `rm` は毎ツール実行ごとに走りますが、フラグが無ければ何もしない no-op です。

## Mac 側のセットアップ

前提: Xcode Command Line Tools（`swiftc`）が入っていること。リモート構成の場合はさらに、母艦へ `ssh user@host` が **鍵認証で** 入れること。

```bash
git clone https://github.com/HirokiMorimoto0713/capslock-blink.git
cd capslock-blink

# 設定を用意する
cp config.example ~/.capslock-blink/config
# ローカル構成（Claude Code も同じ Mac で動かす）ならデフォルトの MOTHERSHIP="local" のままでOK。
# リモート構成なら MOTHERSHIP="user@host" に書き換える。
$EDITOR ~/.capslock-blink/config

bash install-mac.sh
```

capsled は素の CLI バイナリではなく **最小の .app バンドル**（`~/.capslock-blink/capsled.app`）としてビルドされます。素のバイナリだと macOS の TCC が許可ダイアログを出しても入力監視リストへの登録に失敗することがあるためで、バンドルにすると確実に登録されます。

インストールが終わって capsled が起動すると、**「"capsled" で任意のアプリケーションからキー操作を受け取ろうとしています」** というダイアログが出ます。**「"システム設定"を開く」** を押し、入力監視リストに現れた `capsled` をオンにして、反映してください:

```bash
launchctl kickstart -k gui/$(id -u)/dev.capslock-blink.led
```

ダイアログを見逃したときも、この kickstart でもう一度出せます。

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
入力監視の権限が launchd プロセスに効いていません。macOS の TCC は「入力監視」を実行バイナリごとに管理し、ターミナルの子プロセスと launchd 常駐プロセスは別扱いです。入力監視リストの `capsled` をオン（無ければ `＋` で `~/.capslock-blink/capsled.app` を追加）にし、`launchctl kickstart -k gui/$(id -u)/dev.capslock-blink.led` で入れ直してください。旧来の `launchctl load` ではなく **`launchctl bootstrap gui/$(id -u)`** で登録するのも、TCC のドメインを合わせるうえで重要です（install-mac.sh はこれを使っています）。

**ずっと点滅しっぱなし / 消えない**
`cat /tmp/claude-blink-state` と `~/.claude/blink-flag`（リモート構成の場合は母艦側）を突き合わせます。（リモート構成の場合）SSH が切れていると poll が更新できません → `tail /tmp/capsled-poll.err.log`。

**許可の状態をやり直したい**
`tccutil reset ListenEvent dev.capslock-blink.capsled` で capsled の入力監視の記録だけをリセットできます（.app バンドル化により identifier 指定が効きます）。リセット後に kickstart するとダイアログが再表示されます。

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

## 点滅を手動で止める

点滅中に **CapsLock を素早く2回押す** と消灯します。次のプロンプトを待たずに、その場で黙らせたいときに使ってください。

- 仕組み: `capsled` が CapsLock の押下を監視していて、0.6 秒以内の2回押しを検知すると `/tmp/claude-blink-dismiss` を作成。`poll.sh` がこれを見つけて母艦側の `blink-flag` を削除し、ローカルの状態も `off` にします。母艦のフラグを消さないと `poll.sh` が次のポーリングで `on` に戻してしまうため、Mac ローカルだけでなく母艦側まで確実に消す設計です。
- CapsLock の入力状態（大文字/小文字）自体は2回押しで元に戻るので、キーボードの挙動に影響は残りません。
- 点滅していないとき（`state` が `on` 以外）は CapsLock の通常入力に一切干渉しません。
- 注意: Mac 内蔵キーボードは誤爆防止のため、CapsLock の短すぎる押下をハードウェアレベルで無視することがあります。反応しないときは、やや長めに2回押してみてください。
- これは恒久的なミュートではありません。次に応答が完了する、または許可待ちになると、また点滅が始まります。

## 調整

- 点滅の速さ: `src/capsled.swift` の `0.4`（秒）を変更して `bash install-mac.sh` を再実行。
- 監視間隔: `~/.capslock-blink/config` の `INTERVAL`。

## ライセンス

MIT
