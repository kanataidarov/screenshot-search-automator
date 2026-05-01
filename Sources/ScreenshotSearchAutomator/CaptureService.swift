import AppKit
import CoreGraphics
import ScreenCaptureKit

struct CaptureService {
    @MainActor
    func ensureScreenCaptureAccess(promptIfNeeded: Bool = true) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        guard promptIfNeeded else {
            return false
        }

        return CGRequestScreenCaptureAccess()
    }

    @MainActor
    func capturePNG(in globalRect: CGRect) async throws -> Data {
        guard ensureScreenCaptureAccess(promptIfNeeded: false) else {
            throw CaptureError.permissionDenied
        }

        let selectionRect = globalRect.standardized
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let fragments = try await captureFragments(in: selectionRect, shareableContent: shareableContent)

        guard !fragments.isEmpty else {
            throw CaptureError.displayUnavailable
        }

        return try compositePNG(from: fragments, selectionRect: selectionRect)
    }

    @MainActor
    private func captureFragments(
        in selectionRect: CGRect,
        shareableContent: SCShareableContent
    ) async throws -> [CaptureFragment] {
        var fragments: [CaptureFragment] = []

        for screen in NSScreen.screens {
            let intersectionRect = screen.frame.intersection(selectionRect)
            if intersectionRect.isNull || intersectionRect.isEmpty {
                continue
            }

            guard let displayID = screen.displayID,
                  let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayUnavailable
            }

            let localRect = CGRect(
                x: intersectionRect.minX - screen.frame.minX,
                y: intersectionRect.minY - screen.frame.minY,
                width: intersectionRect.width,
                height: intersectionRect.height
            )

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = localRect
            configuration.width = max(1, Int(round(localRect.width * screen.backingScaleFactor)))
            configuration.height = max(1, Int(round(localRect.height * screen.backingScaleFactor)))
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            fragments.append(
                CaptureFragment(
                    image: image,
                    intersectionRect: intersectionRect,
                    scale: screen.backingScaleFactor
                )
            )
        }

        return fragments
    }

    private func compositePNG(from fragments: [CaptureFragment], selectionRect: CGRect) throws -> Data {
        let targetScale = fragments.map(\.scale).max() ?? 1
        let pixelWidth = max(1, Int(round(selectionRect.width * targetScale)))
        let pixelHeight = max(1, Int(round(selectionRect.height * targetScale)))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureError.encodingFailed
        }

        context.interpolationQuality = .high

        for fragment in fragments {
            let destinationRect = CGRect(
                x: (fragment.intersectionRect.minX - selectionRect.minX) * targetScale,
                y: (fragment.intersectionRect.minY - selectionRect.minY) * targetScale,
                width: fragment.intersectionRect.width * targetScale,
                height: fragment.intersectionRect.height * targetScale
            )
            context.draw(fragment.image, in: destinationRect)
        }

        guard let compositeImage = context.makeImage() else {
            throw CaptureError.encodingFailed
        }

        let bitmap = NSBitmapImageRep(cgImage: compositeImage)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }

        return pngData
    }
}

private struct CaptureFragment {
    let image: CGImage
    let intersectionRect: CGRect
    let scale: CGFloat
}

enum CaptureError: LocalizedError, Equatable {
    case displayUnavailable
    case encodingFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "Could not resolve the selected display for capture."
        case .encodingFailed:
            return "Could not encode the screenshot as PNG."
        case .permissionDenied:
            return "Screen Recording access is required before the app can capture a selected area."
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}