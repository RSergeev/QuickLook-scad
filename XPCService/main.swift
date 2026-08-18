import Foundation
import os

@objc public protocol ExportedObjectProtocol {
	func render(
		file: URL,
		size: CGSize,
		callback: @escaping (Data?, String?) -> Void
	)
}

private let logger = Logger(
	subsystem: "com.levitatingpineapple.PreviewSCAD.XPCService",
	category: "Renderer"
)

private enum RenderError: LocalizedError {
	case openSCADNotInstalled
	case invalidSize
	case processFailed(String)
	case invalidOutput

	var errorDescription: String? {
		switch self {
		case .openSCADNotInstalled:
			return "OpenSCAD is not installed in /Applications."
		case .invalidSize:
			return "Quick Look requested an invalid image size."
		case .processFailed(let details):
			return details.isEmpty ? "OpenSCAD rendering failed." : details
		case .invalidOutput:
			return "OpenSCAD did not produce a PNG image."
		}
	}
}

private final class ExportedObject: NSObject, ExportedObjectProtocol {
	private let executableURL = URL(
		fileURLWithPath: "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD"
	)

	@objc func render(
		file: URL,
		size: CGSize,
		callback: @escaping (Data?, String?) -> Void
	) {
		do {
			callback(try render(file: file, size: size), nil)
		} catch {
			let message = error.localizedDescription
			logger.error("Render failed for \(file.lastPathComponent, privacy: .public): \(message, privacy: .public)")
			callback(nil, message)
		}
	}

	private func render(file: URL, size: CGSize) throws -> Data {
		guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
			throw RenderError.openSCADNotInstalled
		}

		let width = Int(size.width.rounded())
		let height = Int(size.height.rounded())
		guard width > 0, height > 0 else {
			throw RenderError.invalidSize
		}

		let temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: temporaryDirectory,
			withIntermediateDirectories: true
		)
		defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
		let outputURL = temporaryDirectory.appendingPathComponent("preview.png")

		let process = Process()
		let logPipe = Pipe()
		process.standardOutput = logPipe
		process.standardError = logPipe
		process.executableURL = executableURL
		process.arguments = [
			"--backend", "Manifold",
			"--imgsize", "\(width),\(height)",
			"--colorscheme", "Starnight",
			"--export-format", "png",
			"--o", outputURL.path,
			file.path
		]

		try process.run()
		let logData = logPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		guard process.terminationReason == .exit, process.terminationStatus == 0 else {
			let details = String(data: logData, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			throw RenderError.processFailed(details)
		}

		let imageData = try Data(contentsOf: outputURL)
		guard imageData.starts(with: [0x89, 0x50, 0x4e, 0x47]) else {
			throw RenderError.invalidOutput
		}
		return imageData
	}
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
	func listener(
		_ listener: NSXPCListener,
		shouldAcceptNewConnection connection: NSXPCConnection
	) -> Bool {
		connection.exportedInterface = NSXPCInterface(with: ExportedObjectProtocol.self)
		connection.exportedObject = ExportedObject()
		connection.resume()
		return true
	}
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
