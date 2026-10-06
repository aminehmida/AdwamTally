import AppKit
import SwiftUI

// MARK: - Popup size

enum PopupSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Base point size for the count number; other metrics scale from it.
    var countFontSize: CGFloat {
        switch self {
        case .small: return 34
        case .medium: return 52
        case .large: return 76
        }
    }

    var labelFontSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 17
        case .large: return 22
        }
    }

    var padding: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 18
        case .large: return 26
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .small: return 120
        case .medium: return 170
        case .large: return 230
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 24
        case .large: return 30
        }
    }

    /// Upper bound on the card's content width so long labels wrap instead of
    /// stretching the popup across the screen.
    var maxContentWidth: CGFloat {
        switch self {
        case .small: return 220
        case .medium: return 300
        case .large: return 380
        }
    }

    /// Transparent padding around the card so the drop shadow isn't clipped by
    /// the (tightly-sized) panel.
    var shadowMargin: CGFloat { 26 }
}

// MARK: - Popup position (9-grid)

enum PopupPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Origin (bottom-left, Cocoa coordinates) for a window of `size` inside
    /// `screen`'s visible frame, honoring `margin` from the edges.
    func origin(for size: CGSize, in screen: NSScreen, margin: CGFloat) -> CGPoint {
        let vf = screen.visibleFrame
        let x: CGFloat
        switch self {
        case .topLeft, .middleLeft, .bottomLeft:
            x = vf.minX + margin
        case .topCenter, .center, .bottomCenter:
            x = vf.midX - size.width / 2
        case .topRight, .middleRight, .bottomRight:
            x = vf.maxX - size.width - margin
        }
        let y: CGFloat
        switch self {
        case .topLeft, .topCenter, .topRight:
            y = vf.maxY - size.height - margin
        case .middleLeft, .center, .middleRight:
            y = vf.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = vf.minY + margin
        }
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Modifier keys (left/right distinguished by keyCode)

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case leftShift, rightShift
    case leftControl, rightControl
    case leftOption, rightOption
    case leftCommand, rightCommand

    var id: String { rawValue }

    /// Hardware virtual keycode reported by a `.flagsChanged` NSEvent.
    var keyCode: UInt16 {
        switch self {
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftCommand: return 55
        case .rightCommand: return 54
        }
    }

    /// The device-independent flag this key contributes to `modifierFlags`.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .leftShift, .rightShift: return .shift
        case .leftControl, .rightControl: return .control
        case .leftOption, .rightOption: return .option
        case .leftCommand, .rightCommand: return .command
        }
    }

    /// Device-*dependent* bit in `modifierFlags.rawValue` — distinguishes the
    /// exact physical key (left vs right) and reflects its true pressed state,
    /// so we never drift out of sync tracking up/down transitions ourselves.
    var deviceMask: UInt {
        switch self {
        case .leftControl:  return 0x00000001
        case .leftShift:    return 0x00000002
        case .rightShift:   return 0x00000004
        case .leftCommand:  return 0x00000008
        case .rightCommand: return 0x00000010
        case .leftOption:   return 0x00000020
        case .rightOption:  return 0x00000040
        case .rightControl: return 0x00002000
        }
    }

    /// Union of every monitored device-dependent modifier bit.
    static let allDeviceMask: UInt = allCases.reduce(0) { $0 | $1.deviceMask }

    var displayName: String {
        switch self {
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        }
    }

    var symbol: String {
        switch self {
        case .leftShift, .rightShift: return "⇧"
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        case .leftCommand, .rightCommand: return "⌘"
        }
    }

    static func from(keyCode: UInt16) -> ModifierKey? {
        allCases.first { $0.keyCode == keyCode }
    }
}

// MARK: - Actions

enum CounterAction: String, Codable, CaseIterable, Identifiable {
    case increment
    case next
    case previous
    case resetCurrent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .increment: return "Increment (+1)"
        case .next: return "Next counter"
        case .previous: return "Previous counter"
        case .resetCurrent: return "Reset current"
        }
    }
}

// MARK: - Counter

enum AfterTarget: String, Codable, CaseIterable, Identifiable {
    case resetToZero
    case keepCounting

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .resetToZero: return "Reset to 0"
        case .keepCounting: return "Keep counting"
        }
    }
}

struct Counter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String
    var isRTL: Bool = false
    var colorHex: String = "#4C8DFF"
    var target: Int? = nil
    var afterTarget: AfterTarget = .resetToZero
    var autoAdvance: Bool = true
    var count: Int = 0
    var enabled: Bool = true

    var hasTarget: Bool { (target ?? 0) > 0 }

    var isComplete: Bool {
        guard let t = target, t > 0 else { return false }
        return count >= t
    }

    init(id: UUID = UUID(), label: String, isRTL: Bool = false, colorHex: String = "#4C8DFF",
         target: Int? = nil, afterTarget: AfterTarget = .resetToZero, autoAdvance: Bool = true,
         count: Int = 0, enabled: Bool = true) {
        self.id = id
        self.label = label
        self.isRTL = isRTL
        self.colorHex = colorHex
        self.target = target
        self.afterTarget = afterTarget
        self.autoAdvance = autoAdvance
        self.count = count
        self.enabled = enabled
    }

    // Tolerant decoding so state saved before a field existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        isRTL = try c.decodeIfPresent(Bool.self, forKey: .isRTL) ?? false
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4C8DFF"
        target = try c.decodeIfPresent(Int.self, forKey: .target)
        afterTarget = try c.decodeIfPresent(AfterTarget.self, forKey: .afterTarget) ?? .resetToZero
        autoAdvance = try c.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? true
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

// MARK: - Settings

struct AppSettings: Codable {
    var bindings: [CounterAction: ModifierKey] = [
        .increment: .rightControl,
        .next: .leftCommand
    ]
    var popupSize: PopupSize = .medium
    var popupPosition: PopupPosition = .topRight
    var chimeEnabled: Bool = false
    var chimeName: String = "Tink"
    var autoHideSeconds: Double = 3.0
    var showPattern: Bool = true
    var patternOpacity: Double = 0.08
    /// Overall opacity of the whole popup background (glass + tint + pattern).
    /// Text stays fully opaque regardless.
    var backgroundOpacity: Double = 0.75
    var showBorder: Bool = true
    /// Clear all counts once a new day starts (see AppState.resetIfNewDay).
    var resetAfterMidnight: Bool = true

    init() {}

    // Tolerant decoding so settings saved before a field existed still load
    // (otherwise the whole persisted state would fall back to defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let def = AppSettings()
        bindings = try c.decodeIfPresent([CounterAction: ModifierKey].self, forKey: .bindings) ?? def.bindings
        popupSize = try c.decodeIfPresent(PopupSize.self, forKey: .popupSize) ?? def.popupSize
        popupPosition = try c.decodeIfPresent(PopupPosition.self, forKey: .popupPosition) ?? def.popupPosition
        chimeEnabled = try c.decodeIfPresent(Bool.self, forKey: .chimeEnabled) ?? def.chimeEnabled
        chimeName = try c.decodeIfPresent(String.self, forKey: .chimeName) ?? def.chimeName
        autoHideSeconds = try c.decodeIfPresent(Double.self, forKey: .autoHideSeconds) ?? def.autoHideSeconds
        showPattern = try c.decodeIfPresent(Bool.self, forKey: .showPattern) ?? def.showPattern
        patternOpacity = try c.decodeIfPresent(Double.self, forKey: .patternOpacity) ?? def.patternOpacity
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? def.backgroundOpacity
        showBorder = try c.decodeIfPresent(Bool.self, forKey: .showBorder) ?? def.showBorder
        resetAfterMidnight = try c.decodeIfPresent(Bool.self, forKey: .resetAfterMidnight) ?? def.resetAfterMidnight
    }

    /// Reverse lookup: which action (if any) is bound to a given modifier key.
    func action(for key: ModifierKey) -> CounterAction? {
        bindings.first(where: { $0.value == key })?.key
    }
}

// MARK: - Persisted document

struct PersistedState: Codable {
    var counters: [Counter]
    var activeIndex: Int
    var settings: AppSettings
    var lastCountAt: Date? = nil
}

// MARK: - Defaults

enum Defaults {
    static func counters() -> [Counter] {
        [
            Counter(label: "سُبْحَانَ اللّٰه", isRTL: true, colorHex: "#34C759", target: 33),
            Counter(label: "الْحَمْدُ لِلّٰه", isRTL: true, colorHex: "#4C8DFF", target: 33),
            Counter(label: "اللّٰهُ أَكْبَر", isRTL: true, colorHex: "#FF9F0A", target: 34)
        ]
    }
}

// MARK: - Color hex helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
        } else {
            r = 0.3; g = 0.55; b = 1.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        guard s.count == 6 else { return NSColor.systemBlue }
        return NSColor(
            srgbRed: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: 1
        )
    }

    var toHex: String {
        guard let c = usingColorSpace(.sRGB) else { return "#4C8DFF" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
