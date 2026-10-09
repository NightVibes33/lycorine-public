import SwiftUI
import UniformTypeIdentifiers

/// One log snapshot exported using the Files document picker, not a share sheet.
struct LycorineLogExport: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = bytes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func snapshot() throws -> LycorineLogExport {
        let source = LycorineDiagnosticLog.shared.currentFileURL
        return LycorineLogExport(data: try Data(contentsOf: source))
    }
}
