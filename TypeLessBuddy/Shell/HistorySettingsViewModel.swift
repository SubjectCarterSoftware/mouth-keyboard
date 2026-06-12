import Foundation

/// Owns the saved-history browsing state and the file operations that used to
/// live inline in `SetupWindowView`. The capture service and clipboard write
/// are injected so the logic can be unit-tested without touching disk or the
/// real pasteboard.
@MainActor
final class HistorySettingsViewModel: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var selectedEntryURL: URL?
    @Published private(set) var selectedDetail: HistoryEntryDetail?
    @Published var searchQuery = ""
    @Published private(set) var usage: HistoryUsage?
    @Published private(set) var loadError: String?
    @Published private(set) var copyConfirmationVisible = false

    private var copyConfirmationTask: Task<Void, Never>?

    private let historyCaptureService: any HistoryCapturing
    private let configurationProvider: () -> HistoryConfiguration
    private let writeToClipboard: (String) -> Bool

    init(
        historyCaptureService: any HistoryCapturing,
        configuration: @escaping () -> HistoryConfiguration,
        writeToClipboard: @escaping (String) -> Bool = { ClipboardService().writeToClipboard($0) }
    ) {
        self.historyCaptureService = historyCaptureService
        self.configurationProvider = configuration
        self.writeToClipboard = writeToClipboard
    }

    func reloadEntries() {
        copyConfirmationTask?.cancel()
        copyConfirmationVisible = false

        do {
            let configuration = configurationProvider()
            let entries = try historyCaptureService.listEntries(configuration: configuration)
            self.entries = entries
            usage = try? historyCaptureService.storageUsage(configuration: configuration)
            loadError = nil

            if let selectedEntryURL,
               entries.contains(where: { $0.fileURL == selectedEntryURL }) {
                loadEntryDetail(for: selectedEntryURL)
                return
            }

            if let firstEntry = entries.first {
                selectedEntryURL = firstEntry.fileURL
                loadEntryDetail(for: firstEntry.fileURL)
            } else {
                selectedEntryURL = nil
                selectedDetail = nil
            }
        } catch {
            entries = []
            usage = nil
            selectedEntryURL = nil
            selectedDetail = nil
            loadError = error.localizedDescription
        }
    }

    func selectEntry(_ fileURL: URL) {
        selectedEntryURL = fileURL
        copyConfirmationTask?.cancel()
        copyConfirmationVisible = false
        loadEntryDetail(for: fileURL)
    }

    private func loadEntryDetail(for fileURL: URL) {
        do {
            selectedDetail = try historyCaptureService.loadEntryDetail(at: fileURL)
            loadError = nil
            copyConfirmationVisible = false
        } catch {
            selectedDetail = nil
            loadError = error.localizedDescription
            copyConfirmationVisible = false
        }
    }

    func copySelectedEntry() {
        guard let text = selectedDetail?.primaryText, !text.isEmpty else {
            return
        }

        guard writeToClipboard(text) else {
            return
        }

        copyConfirmationTask?.cancel()
        copyConfirmationVisible = true
        copyConfirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            copyConfirmationVisible = false
        }
    }

    func deleteEntry(_ fileURL: URL) {
        do {
            try historyCaptureService.deleteEntry(at: fileURL)
            if selectedEntryURL == fileURL {
                selectedEntryURL = nil
                selectedDetail = nil
            }
            reloadEntries()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func clearAll() {
        do {
            try historyCaptureService.deleteAllEntries(configuration: configurationProvider())
            selectedEntryURL = nil
            selectedDetail = nil
            reloadEntries()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Entries filtered by the search query (matched against the preview snippet).
    var filteredEntries: [HistoryEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.previewText.lowercased().contains(query) }
    }

    /// Filtered entries bucketed into day groups (Today / Yesterday / date), newest first.
    var groupedEntries: [(label: String, entries: [HistoryEntry])] {
        var order: [String] = []
        var buckets: [String: [HistoryEntry]] = [:]
        for entry in filteredEntries {
            let label = HistoryFormat.dayLabel(for: entry.createdAt)
            if buckets[label] == nil {
                buckets[label] = []
                order.append(label)
            }
            buckets[label]?.append(entry)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var usageDescription: String? {
        guard let usage else { return nil }
        let used = ByteCountFormatter.string(fromByteCount: usage.totalBytes, countStyle: .file)
        return "\(used) used"
    }

    /// The detail for the current selection, but only when that selection is
    /// still visible under the active search filter.
    var filteredSelectionDetail: HistoryEntryDetail? {
        guard let url = selectedEntryURL,
              filteredEntries.contains(where: { $0.fileURL == url }) else {
            return nil
        }
        return selectedDetail
    }
}
