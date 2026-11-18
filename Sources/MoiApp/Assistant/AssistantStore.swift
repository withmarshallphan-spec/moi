import Foundation

/// Stores Moi's personal notes. Legacy conversation metadata is retained only so
/// existing backups remain lossless after the chat feature was removed.
@MainActor
final class AssistantStore: ObservableObject {
    static let shared = AssistantStore()

    @Published private(set) var storageError: String?
    private var readOnly = false
    @Published private(set) var notes: [KnowledgeNote] = []

    private var legacyConversations: [ConversationMetadata] = []
    private var legacyUsage: [AIUsageRecord] = []
    private let folder: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(folder: URL? = nil) {
        self.folder = folder ?? MoiPaths.root.appendingPathComponent("Assistant", isDirectory: true)
        self.indexURL = self.folder.appendingPathComponent("index.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let index = try LocalStorage.load(AssistantIndex.self, from: indexURL, default: AssistantIndex(conversations: [], notes: [], usage: []))
            legacyConversations = index.conversations
            legacyUsage = index.usage
            notes = index.notes.sorted { $0.updatedAt > $1.updatedAt }
        } catch { readOnly = true; storageError = "Original notes preserved; editing disabled. " + error.localizedDescription }
    }

    @discardableResult
    func saveNote(_ note: KnowledgeNote) -> Bool {
        guard !readOnly else { return false }
        let previous = notes
        var note = note; note.updatedAt = Date()
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note }
        else { notes.insert(note, at: 0) }
        if saveIndex() { return true }
        notes = previous; return false
    }

    @discardableResult
    func deleteNote(_ id: UUID) -> Bool {
        guard !readOnly else { return false }
        let previous = notes
        notes.removeAll { $0.id == id }
        if saveIndex() { return true }
        notes = previous; return false
    }

    func searchNotes(_ query: String) -> [KnowledgeNote] {
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    func makeArchive() throws -> AssistantArchive {
        guard !readOnly else { throw MoiError.message(storageError ?? "Notes are in read-only recovery mode.") }
        var files: [String: ConversationFile] = [:]
        for item in legacyConversations {
            let file = try decoder.decode(ConversationFile.self, from: Data(contentsOf: conversationURL(item.id)))
            guard file.id == item.id else { throw MoiError.message("Legacy conversation identifier mismatch. Export stopped; original files preserved.") }
            files[item.id.uuidString] = file
        }
        return AssistantArchive(
            index: AssistantIndex(
                conversations: legacyConversations,
                notes: notes,
                usage: legacyUsage
            ),
            conversations: files
        )
    }

    func reload() {
        do {
            let index = try LocalStorage.load(AssistantIndex.self, from: indexURL, default: AssistantIndex(conversations: [], notes: [], usage: []))
            legacyConversations = index.conversations; legacyUsage = index.usage
            notes = index.notes.sorted { $0.updatedAt > $1.updatedAt }
            readOnly = false; storageError = nil
        } catch { readOnly = true; storageError = error.localizedDescription }
    }

    private func saveIndex() -> Bool {
        guard !readOnly else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let index = AssistantIndex(
                conversations: legacyConversations,
                notes: notes,
                usage: legacyUsage
            )
            try encoder.encode(index).write(to: indexURL, options: .atomic)
            storageError = nil; return true
        } catch {
            storageError = error.localizedDescription; return false
        }
    }

    private func conversationURL(_ id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }
}
