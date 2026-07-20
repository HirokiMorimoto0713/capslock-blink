import Foundation
import IOKit.hid

// CapsLock LED を状態ファイルに従って点滅/消灯させる常駐プロセス。
// /tmp/claude-blink-state が "on" なら 400ms ごとにトグル、それ以外は消灯。

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let devMatch: [String: Any] = [
    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
]
IOHIDManagerSetDeviceMatching(manager, devMatch as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

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
var phase = false
var lastToggle = Date()
setLED(false)

while true {
    let state = (try? String(contentsOfFile: statePath, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "off"
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
    usleep(50_000)
}
