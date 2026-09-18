import SwiftUI

struct DocumentDestinationView: View {
    @ObservedObject var shelf: ShelfManager
    let item: ShelfItem
    @State private var directory = DocumentFileOperations.documents
    @State private var folders: [URL] = []
    @State private var loading = true
    @State private var error: String?
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var refreshID = UUID()

    private var busy: Bool { shelf.busyIDs.contains(item.id) }
    private var root: URL { DocumentFileOperations.documents }
    private var pathLabel: String {
        let relative = directory.path.dropFirst(root.path.count)
        return "Documenti" + relative.replacingOccurrences(of: "/", with: " › ")
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.arrow.down").foregroundColor(.cyan)
                Text(item.displayName).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button { shelf.moveItem = nil } label: { Image(systemName: "xmark") }
                    .help("Chiudi selezione cartella")
            }
            .font(.system(size: 11, weight: .medium))

            HStack(spacing: 6) {
                Button { directory = directory.deletingLastPathComponent() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(directory == root)
                Button { directory = root } label: { Image(systemName: "house") }
                    .help("Torna a Documenti")
                Text(pathLabel).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button { refreshID = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Aggiorna cartelle")
            }
            .font(.system(size: 10)).foregroundColor(.white.opacity(0.65))

            ScrollView {
                if loading {
                    ProgressView().controlSize(.small)
                } else if let error {
                    Text(error).font(.system(size: 10)).foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if folders.isEmpty {
                    Text("Nessuna sottocartella · puoi spostare qui")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(folders, id: \.self) { folder in
                            Button { directory = folder } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill").foregroundColor(.cyan.opacity(0.8))
                                    Text(folder.lastPathComponent).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.4))
                                }
                                .font(.system(size: 11))
                                .padding(.horizontal, 6).padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Nuova cartella") { folderName = ""; creatingFolder = true }
                    .disabled(loading || error != nil)
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.mini) }
                Button("Sposta qui") { shelf.move(item, into: directory) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(loading || error != nil || directory.standardizedFileURL == URL(fileURLWithPath: item.path).deletingLastPathComponent().standardizedFileURL)
            }
            .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .disabled(busy)
        .task(id: directory.path + refreshID.uuidString) { await loadFolders() }
        .alert("Nuova cartella", isPresented: $creatingFolder) {
            TextField("Nome cartella", text: $folderName)
            Button("Annulla", role: .cancel) {}
            Button("Crea") {
                let parent = directory
                let name = folderName
                Task {
                    let result = await Task.detached(priority: .userInitiated) {
                        Result { try DocumentFileOperations.createFolder(named: name, in: parent) }
                    }.value
                    switch result {
                    case .success(let created): directory = created
                    case .failure(let failure): shelf.actionMessage = failure.localizedDescription
                    }
                }
            }
        } message: { Text("La cartella verrà creata in " + pathLabel) }
    }

    @MainActor
    private func loadFolders() async {
        let requested = directory
        loading = true
        error = nil
        let result = await Task.detached(priority: .userInitiated) {
            Result { try DocumentFileOperations.folders(in: requested) }
        }.value
        guard !Task.isCancelled, directory == requested else { return }
        loading = false
        switch result {
        case .success(let children): folders = children
        case .failure:
            folders = []
            error = "Impossibile leggere questa cartella. Verifica l’accesso di Dynamic Island in Impostazioni di Sistema → Privacy e sicurezza → File e cartelle, poi premi aggiorna."
        }
    }
}
