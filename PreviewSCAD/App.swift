import SwiftUI
import UniformTypeIdentifiers

// TODO: Add preview configuration using app group user defaults

@main
struct PreviewSCADApp: App {
	var body: some Scene {
		DocumentGroup(newDocument: SCADDocument()) { file in
			ContentView(document: file.$document)
		}
	}
}

struct ContentView: View {
	@Binding var document: SCADDocument

	var body: some View {
		TextEditor(text: $document.text)
	}
}

struct SCADDocument {
	var text = String()
}

extension SCADDocument: FileDocument {
	static var readableContentTypes: [UTType] { [UTType(exportedAs: "org.openscad.scad")] }

	init(configuration: ReadConfiguration) throws {
		if let data = configuration.file.regularFileContents,
		   let string = String(data: data, encoding: .utf8) {
			text = string
		} else {
			throw CocoaError(.fileReadCorruptFile)
		}
	}
	
	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
	}
}
