#!/bin/bash
# blink フラグを監視し、Mac ローカルの状態ファイルに on/off を書く。
#
# 2つのモードに対応する:
#   - ローカルモード（MOTHERSHIP 未設定 or 空 or "local"）:
#     Claude Code も同じ Mac 上で動く前提で、ローカルの flag ファイルを直接見る。SSH 不要。
#   - リモートモード（MOTHERSHIP に user@host）:
#     母艦（Claude Code が動く別マシン）の blink フラグを SSH で監視する。
#     SSH 接続は ControlMaster で再利用して軽量化する。
#
# 設定は環境変数 CAPSLOCK_BLINK_CONFIG、なければ ~/.capslock-blink/config から読む。

CONFIG="${CAPSLOCK_BLINK_CONFIG:-$HOME/.capslock-blink/config}"
[ -f "$CONFIG" ] && . "$CONFIG"

: "${MOTHERSHIP:=local}"
: "${FLAG_PATH:=~/.claude/blink-flag}"
: "${STATE:=/tmp/claude-blink-state}"
: "${INTERVAL:=1}"
: "${DISMISS:=/tmp/claude-blink-dismiss}"

if [ -z "$MOTHERSHIP" ] || [ "$MOTHERSHIP" = "local" ]; then
    LOCAL_MODE=1
    # ローカルモードでは自分のシェルで展開するので ~ を $HOME に置き換えておく
    FLAG_LOCAL="${FLAG_PATH/#\~/$HOME}"
else
    LOCAL_MODE=0
    CTL="/tmp/claude-blink-ssh-%r@%h:%p"
    SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=300
              -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
fi

while true; do
    if [ "$LOCAL_MODE" = 1 ]; then
        if [ -f "$DISMISS" ]; then
            # CapsLock 2回押しによる手動解除
            rm -f "$FLAG_LOCAL"
            rm -f "$DISMISS"
            echo off > "$STATE"
        elif [ -f "$FLAG_LOCAL" ]; then
            echo on > "$STATE"
        else
            echo off > "$STATE"
        fi
    else
        if [ -f "$DISMISS" ]; then
            # CapsLock 2回押しによる手動解除。SSH の成否に関わらず点滅は止めたまま維持する
            if ssh "${SSH_OPTS[@]}" "$MOTHERSHIP" "rm -f $FLAG_PATH" 2>/dev/null; then
                rm -f "$DISMISS"
            fi
            echo off > "$STATE"
        elif ssh "${SSH_OPTS[@]}" "$MOTHERSHIP" "test -f $FLAG_PATH" 2>/dev/null; then
            echo on > "$STATE"
        else
            echo off > "$STATE"
        fi
    fi
    sleep "$INTERVAL"
done
