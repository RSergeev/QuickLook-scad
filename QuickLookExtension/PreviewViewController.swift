import Cocoa
import os
import Quartz
import XPCService

private let logger = Logger(
	subsystem: "com.levitatingpineapple.PreviewSCAD.QuickLookExtension",
	category: "Preview"
)

private enum PreviewError: LocalizedError {
	case xpc(Error)
	case renderer(String)
	case invalidImage

	var errorDescription: String? {
		switch self {
		case .xpc(let error):
			return "The rendering service failed: \(error.localizedDescription)"
		case .renderer(let message):
			return message
		case .invalidImage:
			return "OpenSCAD did not produce a valid PNG image."
		}
	}
}

@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController {
	private let imageView = NSImageView()

	override func loadView() {
		imageView.imageAlignment = .alignCenter
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
		view = imageView
		preferredContentSize = NSSize(width: 800, height: 600)
	}

	func preparePreviewOfFile(at url: URL) async throws {
		let scale = view.window?.backingScaleFactor
			?? NSScreen.main?.backingScaleFactor
			?? 1
		let size = CGSize(width: 800 * scale, height: 600 * scale)
		let data = try await render(file: url, size: size)

		guard let image = NSImage(data: data) else {
			throw PreviewError.invalidImage
		}

		image.size = NSSize(
			width: image.size.width / scale,
			height: image.size.height / scale
		)
		imageView.image = image
		preferredContentSize = image.size
	}

	private func render(file url: URL, size: CGSize) async throws -> Data {
		let isSecurityScoped = url.startAccessingSecurityScopedResource()
		defer {
			if isSecurityScoped {
				url.stopAccessingSecurityScopedResource()
			}
		}

		return try await withCheckedThrowingContinuation { continuation in
			let connection = NSXPCConnection(
				serviceName: "com.levitatingpineapple.PreviewSCAD.XPCService"
			)
			connection.remoteObjectInterface = NSXPCInterface(with: ExportedObjectProtocol.self)
			connection.resume()

			let proxy = connection.remoteObjectProxyWithErrorHandler { error in
				logger.error("XPC rendering failed: \(error.localizedDescription, privacy: .public)")
				connection.invalidate()
				continuation.resume(throwing: PreviewError.xpc(error))
			}

			guard let renderer = proxy as? ExportedObjectProtocol else {
				connection.invalidate()
				continuation.resume(throwing: PreviewError.renderer("Could not connect to the rendering service."))
				return
			}

			renderer.render(file: url, size: size) { data, errorMessage in
				connection.invalidate()
				if let data {
					continuation.resume(returning: data)
				} else {
					let message = errorMessage ?? "OpenSCAD rendering failed."
					logger.error("\(message, privacy: .public)")
					continuation.resume(throwing: PreviewError.renderer(message))
				}
			}
		}
	}
}
