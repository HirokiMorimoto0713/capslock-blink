#!/bin/bash
# 母艦（Claude Code が動くマシン）の blink フラグを SSH で監視し、
# Mac ローカルの状態ファイルに on/off を書く。
# SSH 接続は ControlMaster で再利用して軽量化する。
#
# 設定は環境変数 CAPSLOCK_BLINK_CONFIG、なければ ~/.capslock-blink/config から読む。

CONFIG="${CAPSLOCK_BLINK_CONFIG:-$HOME/.capslock-blink/config}"
[ -f "$CONFIG" ] && . "$CONFIG"

: "${MOTHERSHIP:?MOTHERSHIP が未設定です（$CONFIG に user@host を書いてください）}"
: "${FLAG_PATH:=~/.claude/blink-flag}"
: "${STATE:=/tmp/claude-blink-state}"
: "${INTERVAL:=1}"
: "${DISMISS:=/tmp/claude-blink-dismiss}"

CTL="/tmp/claude-blink-ssh-%r@%h:%p"
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=300
          -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

while true; do
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
    sleep "$INTERVAL"
done
