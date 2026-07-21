import Foundation
import IOKit.hid

// CapsLock LED を状態ファイルに従って点滅/消灯させる常駐プロセス。
// /tmp/claude-blink-state が "on" なら 400ms ごとにトグル、それ以外は消灯。
// 点滅中に CapsLock を素早く2回押すと、母艦側フラグ削除を伴う手動消灯（dismiss）を発火する。

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let devMatch: [String: Any] = [
    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
]
IOHIDManagerSetDeviceMatching(manager, devMatch as CFDictionary)

func logErr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

// 入力監視（TCC）が未許可だと HID を開けない。CLI バイナリは設定画面の「＋」から
// 追加しても登録されないことがあるため、自分から要求して OS の許可ダイアログを出させる。
if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    logErr("入力監視が未許可のため OS に許可を要求します（ダイアログが出たら許可してください）")
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    logErr("IOHIDManagerOpen 失敗: 0x\(String(openResult, radix: 16))。入力監視の許可を確認してください")
}

let ledMatch: [String: Any] = [
    kIOHIDElementUsagePageKey as String: kHIDPage_LEDs,
    kIOHIDElementUsageKey as String: kHIDUsage_LED_CapsLock
]

// キーボードの抜き差しに耐えるよう、要素はトグルごとに取り直す
func ledElements() -> [(IOHIDDevice, IOHIDElement)] {
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    var result: [(IOHIDDevice, IOHIDElement)] = []
    for device in devices {
        guard let elems = IOHIDDeviceCopyMatchingElements(device, ledMatch as CFDictionary,
            IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else { continue }
        for e in elems { result.append((device, e)) }
    }
    return result
}

func setLED(_ on: Bool) {
    for (device, elem) in ledElements() {
        let v = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, elem, 0, on ? 1 : 0)
        IOHIDDeviceSetValue(device, elem, v)
    }
}

let statePath = "/tmp/claude-blink-state"
let dismissPath = "/tmp/claude-blink-dismiss"
var phase = false
var lastToggle = Date()
var lastCapsLockPress = Date.distantPast
setLED(false)

func readState() -> String {
    return (try? String(contentsOfFile: statePath, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "off"
}

// CapsLock キー押下（down）を検知するコールバック。
// 点滅中（state == "on"）にだけ有効で、0.6秒以内の2回押しで手動解除する。
let capsLockCallback: IOHIDValueCallback = { _, result, _, value in
    guard result == kIOReturnSuccess else { return }
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
        IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardCapsLock) else { return }
    guard IOHIDValueGetIntegerValue(value) != 0 else { return } // キー押下のみ拾う（離した瞬間は無視）

    guard readState() == "on" else {
        // 点滅していないときは通常の CapsLock 入力に一切干渉しない
        lastCapsLockPress = Date.distantPast
        return
    }

    let now = Date()
    if now.timeIntervalSince(lastCapsLockPress) <= 0.6 {
        // 2回押しを検出：母艦フラグ削除を poll.sh に依頼しつつ、Mac 側も即座に消灯する
        FileManager.default.createFile(atPath: dismissPath, contents: nil)
        try? "off".write(toFile: statePath, atomically: true, encoding: .utf8)
        setLED(false)
        phase = false
        lastCapsLockPress = Date.distantPast
    } else {
        lastCapsLockPress = now
    }
}
IOHIDManagerRegisterInputValueCallback(manager, capsLockCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

// 点滅処理は 50ms ごとのタイマーで実行する（HID コールバックを効かせるため while true から RunLoop 駆動に変更）
Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    let state = readState()
    if state == "on" {
        if Date().timeIntervalSince(lastToggle) >= 0.4 {
            phase.toggle()
            setLED(phase)
            lastToggle = Date()
        }
    } else if phase {
        phase = false
        setLED(false)
    }
}

CFRunLoopRun()
