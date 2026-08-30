import AppKit
import CoreImage
import FaviconFinder
import ImageIO
import SwiftUI

final class FaviconService: ObservableObject {
    static let shared = FaviconService()

    private let cache = NSCache<NSString, NSImage>()
    private let colorCache = NSCache<NSString, NSColor>()
    private let sourceURLCache = NSCache<NSString, NSURL>()
    private var isFetching: Set<String> = []
    private var pendingCompletions: [String: [(NSImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 128
        cache.totalCostLimit = 16 * 1024 * 1024
        colorCache.countLimit = 128
        sourceURLCache.countLimit = 128
    }

    func getFavicon(for searchURL: String) -> NSImage? {
        guard let domain = extractDomain(from: searchURL) else { return nil }

        if let cachedFavicon = cache.object(forKey: domain as NSString) {
            return cachedFavicon
        }

        fetchAndCacheFavicon(for: domain)
        return nil
    }

    func getFaviconColor(for searchURL: String) -> Color? {
        guard let domain = extractDomain(from: searchURL) else { return nil }

        if let cachedColor = colorCache.object(forKey: domain as NSString) {
            return Color(cachedColor)
        }

        // If favicon exists but color doesn't, compute it
        if let favicon = cache.object(forKey: domain as NSString) {
            let color = favicon.averageColor()
            colorCache.setObject(color, forKey: domain as NSString)
            return Color(color)
        }

        fetchAndCacheFavicon(for: domain)
        return nil
    }

    func faviconURL(for domain: String) -> URL? {
        let normalizedDomain = normalizeDomain(domain)
        return sourceURLCache.object(forKey: normalizedDomain as NSString).map { $0 as URL }
            ?? canonicalURL(for: normalizedDomain)
    }

    func faviconURL(forSearchURL searchURL: String) -> URL? {
        guard let domain = extractDomain(from: searchURL) else { return nil }
        return canonicalURL(for: domain)
    }

    private func extractDomain(from searchURL: String) -> String? {
        let trimmed = searchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed.replacingOccurrences(of: "{query}", with: "")

        if let host = URL(string: sanitized)?.host {
            return normalizeDomain(host)
        }

        if let host = URL(string: "https://\(sanitized)")?.host {
            return normalizeDomain(host)
        }

        return nil
    }

    private func normalizeDomain(_ domain: String) -> String {
        let lowercased = domain.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private func canonicalURL(for domain: String) -> URL? {
        guard !domain.isEmpty else { return nil }
        return URL(string: "https://\(domain)")
    }

    func fetchFaviconSync(for searchURL: String, completion: @escaping (NSImage?) -> Void) {
        guard let domain = extractDomain(from: searchURL) else {
            completion(nil)
            return
        }
        if let cachedFavicon = cache.object(forKey: domain as NSString) {
            completion(cachedFavicon)
            return
        }
        fetchAndCacheFavicon(for: domain, completion: completion)
    }

    private func fetchAndCacheFavicon(for domain: String, completion: ((NSImage?) -> Void)? = nil) {
        if let cachedFavicon = cache.object(forKey: domain as NSString) {
            completion?(cachedFavicon)
            return
        }

        if let completion {
            pendingCompletions[domain, default: []].append(completion)
        }

        guard !isFetching.contains(domain) else { return }
        isFetching.insert(domain)

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let payload = await self.fetchFaviconPayload(for: domain)
            await MainActor.run {
                self.completeFetch(
                    for: domain,
                    favicon: payload?.image,
                    sourceURL: payload?.sourceURL
                )
            }
        }
    }

    @MainActor
    private func completeFetch(for domain: String, favicon: NSImage?, sourceURL: URL?) {
        if let favicon {
            cache.setObject(favicon, forKey: domain as NSString, cost: favicon.memoryCost)
            colorCache.setObject(favicon.averageColor(), forKey: domain as NSString)
            if let sourceURL {
                sourceURLCache.setObject(sourceURL as NSURL, forKey: domain as NSString)
            }
            objectWillChange.send()
        }

        isFetching.remove(domain)
        let completions = pendingCompletions.removeValue(forKey: domain) ?? []
        for completion in completions {
            completion(favicon)
        }
    }

    private func fetchFaviconPayload(for domain: String) async -> (image: NSImage, data: Data, sourceURL: URL)? {
        guard let siteURL = canonicalURL(for: domain) else { return nil }

        do {
            let favicon = try await FaviconFinder(url: siteURL)
                .fetchFaviconURLs()
                .download()
                .largest()
            guard let faviconImage = favicon.image else { return nil }
            if let downsampled = Self.downsampledPNG(from: faviconImage.data, maxPixelSize: 64) {
                return (downsampled.image, downsampled.data, favicon.url.source)
            }
            return (faviconImage.image, faviconImage.data, favicon.url.source)
        } catch {
            return nil
        }
    }

    private static func downsampledPNG(
        from data: Data,
        maxPixelSize: Int
    ) -> (image: NSImage, data: Data)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceShouldCacheImmediately: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                  ] as CFDictionary
              ),
              let pngData = NSBitmapImageRep(cgImage: cgImage)
              .representation(using: .png, properties: [:])
        else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        return (image, pngData)
    }

    func downloadAndSaveFavicon(
        for domain: String,
        faviconURL _: URL,
        to saveURL: URL,
        completion: @escaping (URL?, Bool) -> Void
    ) {
        let normalizedDomain = normalizeDomain(domain)
        fetchFaviconSync(for: "https://\(normalizedDomain)") { [weak self] favicon in
            guard let self, let favicon, let data = favicon.pngData else {
                completion(nil, false)
                return
            }

            let sourceURL = self.faviconURL(for: normalizedDomain)
            DispatchQueue.global(qos: .utility).async {
                let success = (try? data.write(to: saveURL, options: .atomic)) != nil
                DispatchQueue.main.async {
                    completion(success ? sourceURL : nil, success)
                }
            }
        }
    }
}

extension NSImage {
    fileprivate var memoryCost: Int {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    fileprivate var pngData: Data? {
        guard let tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    func averageColor() -> NSColor {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSColor.gray
        }

        let inputImage = CIImage(cgImage: cgImage)
        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )

        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]
        ) else {
            return NSColor.gray
        }

        guard let outputImage = filter.outputImage else {
            return NSColor.gray
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: CGFloat(bitmap[3]) / 255
        )
    }
}
