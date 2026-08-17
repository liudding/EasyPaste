import Testing
import Foundation
import AppKit
@testable import EasyPaste

/// ImageSizeCache 内存治理单元测试。
///
/// 背景：ImageSizeCache 的三个缓存（全尺寸图 / 缩略图 / 尺寸描述）原先无上限、无淘汰，
/// 预览过的图片全尺寸解码后永久驻留，导致进程 RSS 随预览过的图片数量线性增长（实测 >1.6GB）。
/// 这些用例锁定「缓存有容量上限 + LRU 淘汰 + 缩略图未命中不返回全尺寸图 + 可显式清理」的行为。
///
/// 注意：`image(for:)` / `sizeDescription(for:)` 未命中时会重新解码/计算并重新缓存，
/// 因此验证「淘汰/清理」必须用指针同一性（`===`）或 debug 计数，不能靠再次调用返回值。
/// 自 dataLoader 改造后，所有数据读取都经注入的 `dataLoader`（生产为直读 BlobStore 文件，
/// 测试注入内存 Data 提供者）；`sizeDescription` 未命中为异步填充，需轮询等待。
/// makeClip() 通过 `Clip.init(blobStore:)` 注入临时目录实例，不触碰全局 `BlobStore.shared`。
@Suite
struct ImageSizeCacheTests {

    /// 生成一张有效的小图（32×32 红色），供 Clip 使用。
    /// 用像素缓冲直接构造（不经 lockFocus 绘制）：dataLoader 会在后台队列被调用，
    /// AppKit 绘制上下文非线程安全，lockFocus 后台偶发失败导致异步 fill 静默放弃。
    private func makeImageData() -> Data {
        let width = 32, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 255
            pixels[i + 1] = 0
            pixels[i + 2] = 0
            pixels[i + 3] = 255
        }
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        )!
        pixels.withUnsafeBytes { buf in
            memcpy(rep.bitmapData!, buf.baseAddress!, pixels.count)
        }
        return rep.representation(using: .tiff, properties: [:])!
    }

    /// 构造注入临时 BlobStore 的 Clip：imageData 写入临时目录实例，
    /// 不污染真实 Application Support/blobs，也不触碰全局 `BlobStore.shared`。
    private func makeClip() -> Clip {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_test_blobs/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Clip(kind: .image, imageData: makeImageData(), blobStore: BlobStore(directory: dir))
    }

    /// 等待异步缓存填充（sizeDescription 后台读取 + 主线程回填），最多 ~2s。
    private func waitUntil(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - 全尺寸图缓存：容量上限 + LRU

    @Test func imageCacheEvictsLeastRecentlyUsed() {
        let cache = ImageSizeCache(fullImageCapacity: 2, thumbCapacity: 5)
        cache.dataLoader = { _ in makeImageData() }
        let c1 = makeClip(), c2 = makeClip(), c3 = makeClip()

        let img1 = cache.image(for: c1)!
        let img2 = cache.image(for: c2)!
        _ = cache.image(for: c3) // 超过容量 2 → 淘汰最久未用的 c1

        #expect(cache.debugImageCount == 2)
        #expect(cache.image(for: c2) === img2)
        #expect(cache.image(for: c3) !== img1) // c3 已缓存，与 c1 不同实例
        #expect(cache.image(for: c1) !== img1) // c1 被淘汰：重新解码得到新实例
    }

    @Test func imageCacheTouchKeepsRecentlyUsed() {
        let cache = ImageSizeCache(fullImageCapacity: 2, thumbCapacity: 5)
        cache.dataLoader = { _ in makeImageData() }
        let c1 = makeClip(), c2 = makeClip(), c3 = makeClip()

        let img1 = cache.image(for: c1)!
        let img2 = cache.image(for: c2)!
        _ = cache.image(for: c1) // 重新访问 c1 → c1 变为最新
        let img3 = cache.image(for: c3)! // 淘汰的是 c2

        #expect(cache.image(for: c1) === img1) // c1 仍在缓存，同一实例
        #expect(cache.image(for: c3) === img3)
        #expect(cache.image(for: c2) !== img2) // c2 被淘汰：重新解码得到新实例
    }

    // MARK: - 缩略图未命中不返回全尺寸图

    @Test func thumbnailMissDoesNotReturnFullSizeImage() {
        let cache = ImageSizeCache(fullImageCapacity: 2, thumbCapacity: 5)
        cache.dataLoader = { _ in makeImageData() }
        let clip = makeClip()

        // 全尺寸图已缓存（例如用户预览过）
        _ = cache.image(for: clip)
        #expect(cache.image(for: clip) != nil)

        // 但缩略图未命中时，卡片渲染不应拿到全尺寸位图（避免列表滚动时全尺寸位图驻留）
        #expect(cache.thumbnail(for: clip) == nil)
    }

    // MARK: - 缩略图缓存：容量上限

    @Test func thumbCacheEvictsLeastRecentlyUsed() async {
        let cache = ImageSizeCache(fullImageCapacity: 2, thumbCapacity: 2)
        cache.dataLoader = { _ in makeImageData() }
        let c1 = makeClip(), c2 = makeClip(), c3 = makeClip()

        _ = cache.thumbnail(for: c1)
        _ = cache.thumbnail(for: c2)
        _ = cache.thumbnail(for: c3)

        // 等待后台降采样完成（3 张 32×32 小图，毫秒级；最多 2s）
        await waitUntil(cache.debugThumbCount >= 2)
        // 缩略图完成后缓存数量受容量上限约束
        #expect(cache.debugThumbCount <= 2)
    }

    // MARK: - 显式清理

    @Test func removeClearsCachesForItem() async {
        let cache = ImageSizeCache(fullImageCapacity: 2, thumbCapacity: 5)
        cache.dataLoader = { _ in makeImageData() }
        let clip = makeClip()

        _ = cache.image(for: clip)
        #expect(cache.debugImageCount == 1)

        _ = cache.sizeDescription(for: clip) // 异步填充
        await waitUntil(cache.debugSizeCount == 1)
        #expect(cache.debugSizeCount == 1)

        cache.remove(for: clip.id)
        #expect(cache.debugImageCount == 0)
        #expect(cache.debugSizeCount == 0)
    }
}
