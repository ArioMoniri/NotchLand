//
//  NSScreen+Display.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Small display helpers shared by WindowManager (notch placement) and the
//  Appearance settings display picker.
//

import AppKit

extension NSScreen {
    /// The CoreGraphics display ID backing this screen, if available.
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Whether this screen is the Mac's built-in display. Mirrors the
    /// `CGDisplayIsBuiltin` check used for display preference.
    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// Whether this screen exposes a physical notch — detected via a non-zero
    /// top safe-area inset (macOS 12+).
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
