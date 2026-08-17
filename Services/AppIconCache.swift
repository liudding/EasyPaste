import AppKit
import Foundation
import SwiftData
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

    // MARK: 容量上限（LRU 淘汰）

    /// 全尺寸解码图上限：预览浮层同一时刻只显示一张，4 张足够。
    private let fullImageCapacity: Int
    /// 缩略图上限：卡片横向滚动的可见数量（~10 张），96 张留足预取余量。
    private let thumbCapacity: Int
    /// 尺寸描述上限（纯字符串，极小），防极端情况无限增长。
    private let sizeCapacity: Int

    @ObservationIgnored private let lock = NSLock()
    private var sizeCache: [UUID: String] = [:]
    @ObservationIgnored private var sizeOrder: [UUID] = []   // LRU 队列，末尾 = 最近使用
    @ObservationIgnored private var imageCache: [UUID: NSImage] = [:]
    @ObservationIgnored private var imageOrder: [UUID] = []  // LRU 队列，末尾 = 最近使用
    private var thumbCache: [UUID: NSImage] = [:]
    @ObservationIgnored private var thumbOrder: [UUID] = []  // LRU 队列，末尾 = 最近使用
    @ObservationIgnored private var pendingThumbs: Set<UUID> = []
    @ObservationIgnored private var pendingSizes: Set<UUID> = []

    /// 原始图片数据加载器：按 clip id 直读 BlobStore 文件系统存储。
    /// blob 已从 DB 移出（Task 3），无需再经临时 ModelContext 间接读取；
    /// 测试仍可直接注入内存 Data 提供者。
    @ObservationIgnored var dataLoader: @Sendable (UUID) -> Data? = { id in
        BlobStore.shared.read(id: id, kind: .image)
    }

    init(fullImageCapacity: Int = 4, thumbCapacity: Int = 96, sizeCapacity: Int = 512) {
        self.fullImageCapacity = fullImageCapacity
        self.thumbCapacity = thumbCapacity
        self.sizeCapacity = sizeCapacity
    }

    /// 记录一次访问：把 id 移到 LRU 队列末尾（最近使用）。
    private func touch(_ id: UUID, in order: inout [UUID]) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    /// 超出容量时从队列头（最久未用）逐出，防止缓存无限增长。
    private func evictIfNeeded<Value>(_ cache: inout [UUID: Value], _ order: inout [UUID], capacity: Int) {
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    /// 条目删除/过期时清理对应缓存，避免历史条目被 prune 后其解码位图仍驻留内存。
    func remove(for id: UUID) {
        lock.lock()
        sizeCache.removeValue(forKey: id)
        sizeOrder.removeAll { $0 == id }
        imageCache.removeValue(forKey: id)
        imageOrder.removeAll { $0 == id }
        thumbCache.removeValue(forKey: id)
        thumbOrder.removeAll { $0 == id }
        pendingThumbs.remove(id)
        pendingSizes.remove(id)
        lock.unlock()
    }

    /// 清空全部缓存（用于「清除全部历史」等整库操作）。
    func removeAll() {
        lock.lock()
        sizeCache.removeAll()
        sizeOrder.removeAll()
        imageCache.removeAll()
        imageOrder.removeAll()
        thumbCache.removeAll()
        thumbOrder.removeAll()
        pendingThumbs.removeAll()
        pendingSizes.removeAll()
        lock.unlock()
    }

    /// 测试/诊断：当前各缓存条目数。
    var debugImageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return imageCache.count
    }
    var debugThumbCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return thumbCache.count
    }
    var debugSizeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sizeCache.count
    }

    /// 图片尺寸描述（仅读元数据，不做像素解码）。
    ///
    /// 未命中时返回 nil 并在后台经 `dataLoader` 读取元数据，完成后写缓存，
    /// 经 @Observable（sizeCache 不再忽略）触发卡片 footer 刷新。
    /// 读取走短生命周期临时 context，避免把 externalStorage blob 拉进常驻 context。
    func sizeDescription(for item: Clip) -> String? {
        guard item.kind == .image else { return nil }
        lock.lock()
        if let cached = sizeCache[item.id] {
            touch(item.id, in: &sizeOrder)
            lock.unlock()
            return cached
        }
        let started = pendingSizes.insert(item.id).inserted
        lock.unlock()

        if started {
            let id = item.id
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let data = self?.dataLoader(id) else { return }
                let desc = Self.readSizeDescription(from: data)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lock.lock()
                    if let desc {
                        self.sizeCache[id] = desc
                        self.touch(id, in: &self.sizeOrder)
                        self.evictIfNeeded(&self.sizeCache, &self.sizeOrder, capacity: self.sizeCapacity)
                    }
                    self.pendingSizes.remove(id)
                    self.lock.unlock()
                }
            }
        }
        return nil
    }

    /// 从图片数据读取像素尺寸描述（仅读元数据，不做像素解码）。
    private static func readSizeDescription(from data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return "\(w)\u{00d7}\(h)"
    }

    /// 卡片缩略图：命中缓存立即返回；未命中则后台降采样，完成前返回 nil（占位图）。
    ///
    /// 注意：不再以全尺寸图兜底缩略图——列表滚动时全尺寸位图会驻留内存，
    /// 是此前进程 RSS 突破 1.6GB 的主要来源之一。未命中时渲染占位符，
    /// 缩略图异步生成完成后经 @Observable 触发卡片刷新。
    func thumbnail(for item: Clip, maxPixel: Int = 340) -> NSImage? {
        guard item.kind == .image else { return nil }
        lock.lock()
        if let thumb = thumbCache[item.id] {
            touch(item.id, in: &thumbOrder)
            lock.unlock()
            return thumb
        }
        let started = pendingThumbs.insert(item.id).inserted
        lock.unlock()

        if started {
            let id = item.id
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let data = self?.dataLoader(id) else { return }
                let thumb = Self.downsample(data: data, maxPixel: maxPixel)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lock.lock()
                    if let thumb {
                        self.thumbCache[id] = thumb
                        self.touch(id, in: &self.thumbOrder)
                        self.evictIfNeeded(&self.thumbCache, &self.thumbOrder, capacity: self.thumbCapacity)
                    }
                    self.pendingThumbs.remove(id)
                    self.lock.unlock()
                }
            }
        }
        return nil
    }

    /// 全尺寸图（预览浮层用；首次访问解码一次并缓存，超出容量按 LRU 淘汰）。
    func image(for item: Clip) -> NSImage? {
        guard item.kind == .image else { return nil }
        lock.lock()
        if let cached = imageCache[item.id] {
            touch(item.id, in: &imageOrder)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let data = dataLoader(item.id), let img = NSImage(data: data) else { return nil }
        lock.lock()
        imageCache[item.id] = img
        touch(item.id, in: &imageOrder)
        evictIfNeeded(&imageCache, &imageOrder, capacity: fullImageCapacity)
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
