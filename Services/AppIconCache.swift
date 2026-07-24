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
        let dominantColor: CodableColor?
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

    /// 获取指定 bundleID 的 app icon 主色调（Color 形式，供渲染使用）。
    func dominantColor(forBundleID bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        return entry(forBundleID: bundleID).dominantColor?.color
    }

    /// 获取指定 bundleID 的 app icon 主色调（可编码形式，供持久化到 ClipboardItem）。
    func codableDominantColor(forBundleID bundleID: String?) -> CodableColor? {
        guard let bundleID else { return nil }
        return entry(forBundleID: bundleID).dominantColor
    }

    /// 后台预热一批 bundleID 的 icon 与主色调（含显示尺寸缩放），
    /// 避免卡片首次渲染时在主线程做 NSWorkspace 查询 + TIFF 解码 + 像素采样。
    func warm(bundleIDs: [String], displaySize: CGFloat = 22) {
        let ids = Set(bundleIDs)
        guard !ids.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for id in ids {
                _ = self.icon(forBundleID: id, displaySize: displaySize)
            }
        }
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

    /// 从 app icon 中提取主色调（取中心区域平均颜色），返回可编码的 sRGB 分量。
    private func extractDominantColor(from icon: NSImage) -> CodableColor? {
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
        return CodableColor(
            red: Double(rSum) / Double(count) / 255,
            green: Double(gSum) / Double(count) / 255,
            blue: Double(bSum) / Double(count) / 255
        )
    }
}

/// 缓存图片类型剪贴项的尺寸描述、全尺寸图与卡片缩略图。
/// - 尺寸描述只读 CGImageSource 元数据，不解码像素；
/// - 卡片缩略图未命中时在后台按 340px 降采样，完成后经 @Observable 触发卡片刷新，
///   避免滚动新卡片进入视口时在主线程解码全尺寸大图。
@Observable
final class ImageSizeCache: @unchecked Sendable {
    static let shared = ImageSizeCache()
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var sizeCache: [UUID: String] = [:]
    @ObservationIgnored private var imageCache: [UUID: NSImage] = [:]
    private var thumbCache: [UUID: NSImage] = [:]
    @ObservationIgnored private var pendingThumbs: Set<UUID> = []

    /// 图片尺寸描述（仅读元数据，不做像素解码）。
    func sizeDescription(for item: ClipboardItem) -> String? {
        guard let data = item.imageData else { return nil }
        lock.lock()
        if let cached = sizeCache[item.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let desc = "\(w)\u{00d7}\(h)"

        lock.lock()
        sizeCache[item.id] = desc
        lock.unlock()
        return desc
    }

    /// 卡片缩略图：命中缓存立即返回；未命中则后台降采样（完成前返回已缓存的全尺寸图或 nil）。
    func thumbnail(for item: ClipboardItem, maxPixel: Int = 340) -> NSImage? {
        guard item.kind == .image, let data = item.imageData else { return nil }
        lock.lock()
        if let thumb = thumbCache[item.id] {
            lock.unlock()
            return thumb
        }
        let full = imageCache[item.id]
        let started = pendingThumbs.insert(item.id).inserted
        lock.unlock()

        if started {
            let id = item.id
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let thumb = Self.downsample(data: data, maxPixel: maxPixel)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lock.lock()
                    if let thumb { self.thumbCache[id] = thumb }
                    self.pendingThumbs.remove(id)
                    self.lock.unlock()
                }
            }
        }
        return full
    }

    /// 全尺寸图（预览浮层用；首次访问解码一次并缓存）。
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

    /// 用 ImageIO 按最长边降采样，不解码全尺寸位图，速度快且内存占用小。
    private static func downsample(data: Data, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
