import Cocoa
import os
import QuickLookThumbnailing
import XPCService

private let logger = Logger(
	subsystem: "com.levitatingpineapple.PreviewSCAD.ThumbnailExtension",
	category: "Thumbnail"
)

final class ThumbnailProvider: QLThumbnailProvider {
	override func provideThumbnail(
		for request: QLFileThumbnailRequest,
		_ handler: @escaping (QLThumbnailReply?, Error?) -> Void
	) {
		let connection = NSXPCConnection(
			serviceName: "com.levitatingpineapple.PreviewSCAD.XPCService"
		)
		connection.remoteObjectInterface = NSXPCInterface(with: ExportedObjectProtocol.self)
		connection.resume()

		let proxy = connection.remoteObjectProxyWithErrorHandler { error in
			logger.error("XPC rendering failed: \(error.localizedDescription, privacy: .public)")
			connection.invalidate()
			handler(nil, error)
		}

		guard let renderer = proxy as? ExportedObjectProtocol else {
			connection.invalidate()
			handler(nil, CocoaError(.featureUnsupported))
			return
		}

		renderer.render(file: request.fileURL, size: request.maximumSize) { data, errorMessage in
			connection.invalidate()
			guard let data, let image = NSImage(data: data) else {
				let message = errorMessage ?? "OpenSCAD did not produce a valid PNG image."
				logger.error("\(message, privacy: .public)")
				handler(nil, CocoaError(.fileReadCorruptFile, userInfo: [
					NSLocalizedDescriptionKey: message
				]))
				return
			}

			let reply = QLThumbnailReply(
				contextSize: request.maximumSize,
				currentContextDrawing: {
					image.draw(in: NSRect(origin: .zero, size: request.maximumSize))
					return true
				}
			)
			handler(reply, nil)
		}
	}
}
