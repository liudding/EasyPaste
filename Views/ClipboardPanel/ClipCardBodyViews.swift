import AppKit
import SwiftUI

// MARK: - Color Card Body

struct ColorCardBody: View {
    let item: Clip

    var body: some View {
        Color.clear.overlay(
            Text(item.text ?? "").font(.system(size: 14, weight: .bold))
                .foregroundStyle(isLightColor(item.resolvedColorValue ?? item.kind.defaultColor) ? .black : .white)
        )
    }

    private func isLightColor(_ color: Color) -> Bool {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.5
    }
}

// MARK: - Image Card Body

struct ImageCardBody: View {
    let item: Clip

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = ImageSizeCache.shared.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 6))
                
                // Placeholder icon in center for missing image
                ZStack {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                }
            }
            
            if let sizeDesc = item.imageSizeDescription {
                HStack(spacing: 8) {
                    Text(sizeDesc)
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)  // Larger radius for pill shape
                    
                    Spacer()
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Link Card Body

struct LinkCardBody: View {
    let item: Clip
    let headerColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            if let attr = item.attributedText {
                AttributedTextView(attributedString: attr, maxLines: 4, isSelectable: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let url = item.url {
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.host ?? "").font(.system(size: 11, weight: .bold)).foregroundStyle(headerColor)
                    if let preview = item.previewPlainText, preview != url.absoluteString {
                        Text(preview).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(url.absoluteString).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            } else if let preview = item.previewPlainText {
                Text(preview).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
            } else {
                Text(L10n.cannotPreview).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                Text(item.linkFooterTitle).lineLimit(1).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text(item.linkFooterURL).lineLimit(1).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - File Card Body

struct FileCardBody: View {
    let item: Clip

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: "doc.fill").font(.title3).foregroundStyle(.secondary)
            Text(item.detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Text Card Body

struct TextCardBody: View {
    let item: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let attr = item.attributedText {
                AttributedTextView(attributedString: attr, maxLines: 4, isSelectable: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let preview = item.previewPlainText {
                Text(preview).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
            } else {
                Text(L10n.cannotPreview).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Text("\(item.characterCount)\(L10n.characters)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
