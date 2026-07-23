import AppKit
import Foundation
import SwiftUI

/// 缓存来源 app 的 icon 和主色调，避免每次 SwiftUI 重渲染都调用
/// `NSWorkspace.urlForApplication` + `icon(forFile:)` + 像素采样。
/// 使用 NSLock 保证线程安全，不依赖 MainActor。
final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private struct Entry {
        let icon: NSImage?
        let dominantColor: Color?
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var displayCache: [String: NSImage] = [:]

    /// 获取指定 bundleID 的 app icon（已缩放至指定尺寸，缓存复用）。
    func icon(forBundleID bundleID: String?, displaySize: CGFloat) -> NSImage? {
        guard let bundleID else { return nil }
        let key = "\(bundleID)_\(Int(displaySize))"
        lock.lock()
        if let cached = displayCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let raw = rawIcon(forBundleID: bundleID)
        guard let raw else { return nil }
        let resized = NSImage(size: NSSize(width: displaySize, height: displaySize))
        resized.lockFocus()
        raw.draw(in: NSRect(origin: .zero, size: resized.size),
                 from: NSRect(origin: .zero, size: raw.size),
                 operation: .copy, fraction: 1)
        resized.unlockFocus()

        lock.lock()
        displayCache[key] = resized
        lock.unlock()
        return resized
    }

    /// 获取指定 bundleID 的 app icon（原始尺寸）。
    func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        return rawIcon(forBundleID: bundleID)
    }

    /// 获取指定 bundleID 的 app icon 主色调。
    func dominantColor(forBundleID bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        return entry(forBundleID: bundleID).dominantColor
    }

    private func entry(forBundleID bundleID: String) -> Entry {
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let url else {
            let empty = Entry(icon: nil, dominantColor: nil)
            lock.lock()
            cache[bundleID] = empty
            lock.unlock()
            return empty
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let color = extractDominantColor(from: icon)
        let entry = Entry(icon: icon, dominantColor: color)
        lock.lock()
        cache[bundleID] = entry
        lock.unlock()
        return entry
    }

    private func rawIcon(forBundleID bundleID: String) -> NSImage? {
        entry(forBundleID: bundleID).icon
    }

    /// 从 app icon 中提取主色调（取中心区域平均颜色）。
    private func extractDominantColor(from icon: NSImage) -> Color? {
        guard let tiffData = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        var rSum = 0, gSum = 0, bSum = 0, count = 0
        let cx = Int(rep.pixelsWide / 2), cy = Int(rep.pixelsHigh / 2)
        let half = 8
        for x in (cx - half)..<(cx + half) {
            for y in (cy - half)..<(cy + half) {
                guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh else { continue }
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                rSum += Int(color.redComponent * 255)
                gSum += Int(color.greenComponent * 255)
                bSum += Int(color.blueComponent * 255)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return Color(red: Double(rSum) / Double(count) / 255,
                     green: Double(gSum) / Double(count) / 255,
                     blue: Double(bSum) / Double(count) / 255)
    }
}

/// 缓存图片类型剪贴项的尺寸描述和 NSImage，避免每次访问
/// 都从 imageData 创建 NSImage。
final class ImageSizeCache: @unchecked Sendable {
    static let shared = ImageSizeCache()
    private let lock = NSLock()
    private var sizeCache: [UUID: String] = [:]
    private var imageCache: [UUID: NSImage] = [:]

    func sizeDescription(for item: ClipboardItem) -> String? {
        guard let data = item.imageData else { return nil }
        lock.lock()
        if let cached = sizeCache[item.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let img = NSImage(data: data) else { return nil }
        let s = img.size
        let desc = "\(Int(s.width))\u{00d7}\(Int(s.height))"

        lock.lock()
        sizeCache[item.id] = desc
        imageCache[item.id] = img
        lock.unlock()
        return desc
    }

    /// 获取图片类型的 NSImage（从缓存读取，避免重复解码）。
    func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let data = item.imageData else { return nil }
        lock.lock()
        if let cached = imageCache[item.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let img = NSImage(data: data) else { return nil }
        lock.lock()
        imageCache[item.id] = img
        lock.unlock()
        return img
    }
}
