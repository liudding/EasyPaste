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

    /// 从 app icon 中提取主色调。
    ///
    /// 策略：扫描整个 icon（跳过透明像素），将颜色量化分桶，**优先选取「与浅色主题背景可区分」
    /// （亮度 ≤ 阈值）的桶中占比最大的颜色**——这样能直接从 icon 里挑出天然的深色主色，
    /// 避免取到 icon 中心常见的白字/浅色 logo。仅当 icon 内不存在足够暗的颜色时，
    /// 才回退到占比最大的颜色（交由 `ClipCardView.readableHeaderColor` 压暗处理）。
    private func extractDominantColor(from icon: NSImage) -> CodableColor? {
        guard let tiffData = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }

        // 采样步长：覆盖整个 icon，约 32×32 个采样点（平衡覆盖度与性能，每个 bundleID 仅计算一次）。
        let stepX = max(1, w / 32), stepY = max(1, h / 32)

        // 量化桶：每通道 /32 → 0~7（8 级），key = br*64 + bg*8 + bb（共 512 桶）。
        var buckets: [Int: (rSum: Int, gSum: Int, bSum: Int, count: Int)] = [:]
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent >= 0.5 {
                    let r = Int(color.redComponent * 255)
                    let g = Int(color.greenComponent * 255)
                    let b = Int(color.blueComponent * 255)
                    let br = min(7, r / 32), bg = min(7, g / 32), bb = min(7, b / 32)
                    let key = br * 64 + bg * 8 + bb
                    var bucket = buckets[key] ?? (0, 0, 0, 0)
                    bucket.rSum += r
                    bucket.gSum += g
                    bucket.bSum += b
                    bucket.count += 1
                    buckets[key] = bucket
                }
                x += stepX
            }
            y += stepY
        }
        guard !buckets.isEmpty else { return nil }

        // 计算每个桶的平均色与亮度，转候选列表。
        struct Candidate { let r: Double, g: Double, b: Double, count: Int, luminance: Double }
        var candidates: [Candidate] = []
        for (_, v) in buckets {
            let r = Double(v.rSum) / Double(v.count) / 255
            let g = Double(v.gSum) / Double(v.count) / 255
            let b = Double(v.bSum) / Double(v.count) / 255
            candidates.append(Candidate(
                r: r, g: g, b: b, count: v.count,
                luminance: 0.299 * r + 0.587 * g + 0.114 * b
            ))
        }

        // 阈值与 readableHeaderColor 一致：亮度 ≤ 0.6 视为与浅色背景(white:0.98)可区分。
        let maxLuminance: Double = 0.6
        // 优先：在「足够暗」的候选中取占比最大者（最主流的天然深色，无需后续压暗）。
        if let best = candidates
            .filter({ $0.luminance <= maxLuminance })
            .max(by: { $0.count < $1.count }) {
            return CodableColor(red: best.r, green: best.g, blue: best.b)
        }
        // 兜底：icon 内无足够暗的色，返回占比最大者（由 readableHeaderColor 等比压暗，保色相）。
        if let best = candidates.max(by: { $0.count < $1.count }) {
            return CodableColor(red: best.r, green: best.g, blue: best.b)
        }
        return nil
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
    func sizeDescription(for item: Clip) -> String? {
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
    func thumbnail(for item: Clip, maxPixel: Int = 340) -> NSImage? {
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
    func image(for item: Clip) -> NSImage? {
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
