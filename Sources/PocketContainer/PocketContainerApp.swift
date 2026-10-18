import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

struct IPAFile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var originalName: String
    var storedName: String
    var importedAt: Date = .now
    var byteCount: Int64
}

// MARK: - Library storage

@MainActor
final class IPALibrary: ObservableObject {
    @Published private(set) var files: [IPAFile] = []
    @Published var alertMessage: String?

    private let folderName = "PocketContainerLibrary"
    private let indexName = "ipa-library.json"

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var libraryFolder: URL {
        documents.appendingPathComponent(folderName, isDirectory: true)
    }
    private var indexURL: URL {
        documents.appendingPathComponent(indexName)
    }

    init() {
        do {
            try FileManager.default.createDirectory(
                at: libraryFolder,
                withIntermediateDirectories: true
            )
            load()
        } catch {
            alertMessage = "ÐÐµ ÑÐ´Ð°Ð»Ð¾ÑÑ Ð¾ÑÐºÑÑÑÑ Ð±Ð¸Ð±Ð»Ð¸Ð¾ÑÐµÐºÑ: \(error.localizedDescription)"
        }
    }

    func importFile(at sourceURL: URL) {
        guard sourceURL.pathExtension.lowercased() == "ipa" else {
            alertMessage = "ÐÐ¾Ð¶Ð°Ð»ÑÐ¹ÑÑÐ°, Ð²ÑÐ±ÐµÑÐ¸ ÑÐ°Ð¹Ð» Ñ ÑÐ°ÑÑÐ¸ÑÐµÐ½Ð¸ÐµÐ¼ .ipa."
            return
        }

        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
            let destinationName = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
            let destinationURL = libraryFolder.appendingPathComponent(destinationName)

            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            let item = IPAFile(
                originalName: sourceURL.lastPathComponent,
                storedName: destinationName,
                importedAt: .now,
                byteCount: Int64(values.fileSize ?? 0)
            )
            files.insert(item, at: 0)
            save()
        } catch {
            alertMessage = "ÐÐ¼Ð¿Ð¾ÑÑ Ð½Ðµ ÑÐ´Ð°Ð»ÑÑ: \(error.localizedDescription)"
        }
    }

    func delete(_ item: IPAFile) {
        let url = libraryFolder.appendingPathComponent(item.storedName)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            files.removeAll { $0.id == item.id }
            save()
        } catch {
            alertMessage = "ÐÐµ ÑÐ´Ð°Ð»Ð¾ÑÑ ÑÐ´Ð°Ð»Ð¸ÑÑ ÑÐ°Ð¹Ð»: \(error.localizedDescription)"
        }
    }

    func url(for item: IPAFile) -> URL {
        libraryFolder.appendingPathComponent(item.storedName)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([IPAFile].self, from: data)
            files = decoded
                .filter { FileManager.default.fileExists(atPath: urlForStoredName($0.storedName).path) }
                .sorted { $0.importedAt > $1.importedAt }
        } catch {
            alertMessage = "ÐÐµ ÑÐ´Ð°Ð»Ð¾ÑÑ Ð¿ÑÐ¾ÑÐ¸ÑÐ°ÑÑ ÑÐ¿Ð¸ÑÐ¾Ðº ÑÐ°Ð¹Ð»Ð¾Ð²: \(error.localizedDescription)"
        }
    }

    private func urlForStoredName(_ name: String) -> URL {
        libraryFolder.appendingPathComponent(name)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(files)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            alertMessage = "ÐÐµ ÑÐ´Ð°Ð»Ð¾ÑÑ ÑÐ¾ÑÑÐ°Ð½Ð¸ÑÑ ÑÐ¿Ð¸ÑÐ¾Ðº ÑÐ°Ð¹Ð»Ð¾Ð²: \(error.localizedDescription)"
        }
    }
}

// MARK: - App UI

struct ContentView: View {
    @StateObject private var library = IPALibrary()
    @State private var selectedTab: AppTab = .library
    @State private var showImporter = false
    @State private var searchText = ""

    private let background = Color(red: 0.035, green: 0.045, blue: 0.070)
    private let panel = Color(red: 0.075, green: 0.090, blue: 0.130)
    private let blue = Color(red: 0.25, green: 0.52, blue: 1.0)

    private enum AppTab {
        case library
        case settings
    }

    private var visibleFiles: [IPAFile] {
        guard !searchText.isEmpty else { return library.files }
        return library.files.filter {
            $0.originalName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Group {
                    switch selectedTab {
                    case .library:
                        libraryScreen
                    case .settings:
                        settingsScreen
                    }
                }
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { library.importFile(at: url) }
            case .failure(let error):
                library.alertMessage = "ÐÐµ ÑÐ´Ð°Ð»Ð¾ÑÑ Ð¾ÑÐºÑÑÑÑ ÑÐ°Ð¹Ð»: \(error.localizedDescription)"
            }
        }
        .alert("PocketContainer", isPresented: Binding(
            get: { library.alertMessage != nil },
            set: { if !$0 { library.alertMessage = nil } }
        )) {
            Button("ÐÐ", role: .cancel) { library.alertMessage = nil }
        } message: {
            Text(library.alertMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [blue, Color(red: 0.20, green: 0.35, blue: 0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("PocketContainer")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(selectedTab == .library ? "Ð¢ÐÐÐ¯ ÐÐÐÐÐÐÐ¢ÐÐÐ" : "ÐÐÐ¡Ð¢Ð ÐÐÐÐ")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedTab == .library {
                Button { showImporter = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(blue, in: RoundedRectangle(cornerRadius: 13))
                }
                .accessibilityLabel("ÐÐ¼Ð¿Ð¾ÑÑÐ¸ÑÐ¾Ð²Ð°ÑÑ IPA")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var libraryScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                HStack {
                    Text("ÐÐÐÐÐÐÐ¢ÐÐÐ")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(library.files.count) ÑÐ°Ð¹Ð»Ð¾Ð²")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if visibleFiles.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleFiles) { file in
                            fileRow(file)
                        }
                    }
                }

                Text("PocketContainer ÑÑÐ°Ð½Ð¸Ñ IPA-ÑÐ°Ð¹Ð»Ñ. Ð£ÑÑÐ°Ð½Ð¾Ð²ÐºÐ° Ð¸ Ð·Ð°Ð¿ÑÑÐº IPA Ð¿Ð¾ÐºÐ° Ð½Ðµ ÑÐµÐ°Ð»Ð¸Ð·Ð¾Ð²Ð°Ð½Ñ.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .searchable(text: $searchText, prompt: "ÐÐ¾Ð¸ÑÐº Ð² Ð±Ð¸Ð±Ð»Ð¸Ð¾ÑÐµÐºÐµ")
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ð¢ÐÐÐ ÐÐ ÐÐÐÐÐÐÐÐ¯")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.72))
            Text("ÐÑÑ Ð² Ð¾Ð´Ð½Ð¾Ð¼ Ð¼ÐµÑÑÐµ.")
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Text("ÐÐ¼Ð¿Ð¾ÑÑÐ¸ÑÑÐ¹ IPA-ÑÐ°Ð¹Ð»Ñ Ð¸ ÑÑÐ°Ð½Ð¸ Ð¸Ñ Ð² Ð»Ð¾ÐºÐ°Ð»ÑÐ½Ð¾Ð¹ Ð±Ð¸Ð±Ð»Ð¸Ð¾ÑÐµÐºÐµ.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Button { showImporter = true } label: {
                Label("ÐÐ¼Ð¿Ð¾ÑÑÐ¸ÑÐ¾Ð²Ð°ÑÑ IPA", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(blue, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.23, blue: 0.48), panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34))
                .foregroundStyle(blue)
            Text(searchText.isEmpty ? "ÐÐ¾ÐºÐ° Ð·Ð´ÐµÑÑ Ð¿ÑÑÑÐ¾" : "ÐÐ¸ÑÐµÐ³Ð¾ Ð½Ðµ Ð½Ð°Ð¹Ð´ÐµÐ½Ð¾")
                .font(.system(size: 17, weight: .semibold))
            Text(searchText.isEmpty
                 ? "ÐÐ°Ð¶Ð¼Ð¸ Â«ÐÐ¼Ð¿Ð¾ÑÑÐ¸ÑÐ¾Ð²Ð°ÑÑ IPAÂ», ÑÑÐ¾Ð±Ñ Ð²ÑÐ±ÑÐ°ÑÑ ÑÐ°Ð¹Ð» Ð² Ð¿ÑÐ¸Ð»Ð¾Ð¶ÐµÐ½Ð¸Ð¸ Â«Ð¤Ð°Ð¹Ð»ÑÂ»."
                 : "ÐÐ¾Ð¿ÑÐ¾Ð±ÑÐ¹ Ð¸Ð·Ð¼ÐµÐ½Ð¸ÑÑ Ð·Ð°Ð¿ÑÐ¾Ñ.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if searchText.isEmpty {
                Button("ÐÑÐ±ÑÐ°ÑÑ IPA") { showImporter = true }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(panel, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private func fileRow(_ file: IPAFile) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: "app.dashed")
                    .font(.system(size: 23))
                    .foregroundStyle(blue)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(file.originalName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("\(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file)) Â· \(file.importedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("IPA Â· ÑÑÐ°Ð½Ð¸ÑÑÑ Ð»Ð¾ÐºÐ°Ð»ÑÐ½Ð¾")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(blue)
            }

            Spacer(minLength: 0)

            Menu {
                ShareLink(item: library.url(for: file)) {
                    Label("ÐÐ¾Ð´ÐµÐ»Ð¸ÑÑÑÑ ÑÐ°Ð¹Ð»Ð¾Ð¼", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    library.delete(file)
                } label: {
                    Label("Ð£Ð´Ð°Ð»Ð¸ÑÑ", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 40)
            }
        }
        .padding(13)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var settingsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsRow(
                    icon: "moon.fill",
                    title: "ÐÐ½ÐµÑÐ½Ð¸Ð¹ Ð²Ð¸Ð´",
                    detail: "Ð¢ÑÐ¼Ð½Ð°Ñ ÑÐµÐ¼Ð°"
                )
                settingsRow(
                    icon: "internaldrive.fill",
                    title: "Ð¥ÑÐ°Ð½Ð¸Ð»Ð¸ÑÐµ",
                    detail: "\(library.files.count) IPA-ÑÐ°Ð¹Ð»Ð¾Ð² Ð² Ð¿ÑÐ¸Ð»Ð¾Ð¶ÐµÐ½Ð¸Ð¸"
                )
                settingsRow(
                    icon: "lock.fill",
                    title: "ÐÐ¾Ð½ÑÐ¸Ð´ÐµÐ½ÑÐ¸Ð°Ð»ÑÐ½Ð¾ÑÑÑ",
                    detail: "Ð¤Ð°Ð¹Ð»Ñ ÑÑÐ°Ð½ÑÑÑÑ Ð»Ð¾ÐºÐ°Ð»ÑÐ½Ð¾ Ð½Ð° ÑÑÑÑÐ¾Ð¹ÑÑÐ²Ðµ"
                )
                settingsRow(
                    icon: "info.circle.fill",
                    title: "Ð PocketContainer",
                    detail: "ÐÐ¸ÑÐ½Ð°Ñ ÑÐºÑÐ¿ÐµÑÐ¸Ð¼ÐµÐ½ÑÐ°Ð»ÑÐ½Ð°Ñ Ð²ÐµÑÑÐ¸Ñ"
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("ÐÐÐ ÐÐÐÐ§ÐÐÐÐ¯")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text("ÐÐ¼Ð¿Ð¾ÑÑ Ð¸ ÑÑÐ°Ð½ÐµÐ½Ð¸Ðµ IPA Ð´Ð¾ÑÑÑÐ¿Ð½Ñ. Ð£ÑÑÐ°Ð½Ð¾Ð²ÐºÐ°, Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ Ð¸ Ð·Ð°Ð¿ÑÑÐº ÑÑÐ¾ÑÐ¾Ð½Ð½Ð¸Ñ Ð¿ÑÐ¸Ð»Ð¾Ð¶ÐµÐ½Ð¸Ð¹ Ð½Ðµ ÑÐµÐ°Ð»Ð¸Ð·Ð¾Ð²Ð°Ð½Ñ.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(18)
        }
    }

    private func settingsRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(blue)
                .frame(width: 42, height: 42)
                .background(blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(panel, in: RoundedRectangle(cornerRadius: 17))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(.library, icon: "square.grid.2x2.fill", title: "ÐÐ¸Ð±Ð»Ð¸Ð¾ÑÐµÐºÐ°")
            tabButton(.settings, icon: "gearshape.fill", title: "ÐÐ°ÑÑÑÐ¾Ð¹ÐºÐ¸")
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.28))
    }

    private func tabButton(_ tab: AppTab, icon: String, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selectedTab == tab ? blue : .secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@main
struct PocketContainerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

