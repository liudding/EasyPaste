import Testing
import Foundation
@testable import EasyPaste

final class BlobStoreTests {
    private func makeStore() throws -> (BlobStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_blobstore_tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (BlobStore(directory: dir), dir)
    }

    @Test func writeReadRoundTrip() throws {
        let (store, _) = try makeStore()
        let id = UUID(); let data = Data("hello".utf8)
        store.write(data, for: id, kind: .image)
        #expect(store.read(id: id, kind: .image) == data)
    }

    @Test func writeNilRemovesFile() throws {
        let (store, dir) = try makeStore()
        let id = UUID()
        store.write(Data("x".utf8), for: id, kind: .uti)
        store.write(nil, for: id, kind: .uti)
        #expect(store.read(id: id, kind: .uti) == nil)
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func existsReflectsFilePresence() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        #expect(!store.exists(id: id, kind: .image))
        store.write(Data("img".utf8), for: id, kind: .image)
        #expect(store.exists(id: id, kind: .image))
    }

    @Test func removeAllDeletesAllKinds() throws {
        let (store, dir) = try makeStore()
        let id = UUID()
        for kind in BlobStore.BlobKind.allCases { store.write(Data("\(kind.rawValue)".utf8), for: id, kind: kind) }
        store.remove(for: id)
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func removeAllGlobalClearsEverything() throws {
        let (store, dir) = try makeStore()
        store.write(Data("a".utf8), for: UUID(), kind: .image)
        store.write(Data("b".utf8), for: UUID(), kind: .pasteboard)
        store.removeAll()
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func atomicWriteNeverLeavesPartialFile() throws {
        let (store, dir) = try makeStore()
        let id = UUID()
        store.write(Data(repeating: 0xAB, count: 1024), for: id, kind: .pasteboard)
        // 模拟并发写不同文件不互相破坏
        let group = DispatchGroup()
        for i in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                store.write(Data([UInt8(i)]), for: UUID(), kind: .image)
                group.leave()
            }
        }
        group.wait()
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).count == 9)
    }
}
