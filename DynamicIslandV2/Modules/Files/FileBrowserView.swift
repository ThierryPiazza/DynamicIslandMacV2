import AppKit
import QuickLookUI
import SwiftUI

struct FileBrowserView: View {
  @ObservedObject private var browser = FileBrowserModel.shared
  @ObservedObject var notchState: NotchState
  let shelf: ShelfManager
  @State private var session = UUID()
  @State private var enteringPath = false
  @State private var path = ""
  @FocusState private var searching: Bool

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        Button {
          browser.goBack()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(browser.back.isEmpty).help("Indietro")
        Button {
          browser.goForward()
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(browser.forward.isEmpty).help("Avanti")
        Button {
          if let directory = browser.directory {
            browser.navigate(directory.deletingLastPathComponent())
          }
        } label: {
          Image(systemName: "arrow.up")
        }
        .disabled(!browser.canGoUp).help("Cartella superiore")
        Menu {
          Section("Posizioni") {
            ForEach(browser.locations, id: \.url) { location in
              Button(location.name) { browser.navigate(location.url) }
            }
          }
          Section("Preferiti") {
            ForEach(browser.favorites, id: \.self) { url in
              Button(url.lastPathComponent) { browser.navigate(url) }
            }
          }
          Divider()
          Toggle("Mostra file nascosti", isOn: $browser.showHidden)
          Button("Vai alla cartella…") {
            path = browser.directory?.path ?? ""
            enteringPath = true
          }
          Button("Aggiungi cartella…") { browser.chooseFolder() }
          if let current = browser.directory, browser.favorites.contains(current) {
            Button("Rimuovi dai preferiti") { browser.removeFavorite(current) }
          }
        } label: {
          Image(systemName: "internaldrive")
        }
        .help("Posizioni, dischi e preferiti")
        Spacer(minLength: 0)
        Button {
          browser.reload(force: true)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(browser.directory == nil).help("Aggiorna")
        Button {
          browser.chooseFolder()
        } label: {
          Image(systemName: "plus")
        }.help("Aggiungi cartella")
        Button {
          notchState.collapse()
        } label: {
          Image(systemName: "xmark")
        }.help("Chiudi File")
      }.buttonStyle(.plain)
      if enteringPath {
        HStack {
          TextField("Percorso: / oppure ~/Documents", text: $path)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              browser.goToPath(path)
              enteringPath = false
            }
          Button("Vai") {
            browser.goToPath(path)
            enteringPath = false
          }
          Button {
            enteringPath = false
          } label: {
            Image(systemName: "xmark")
          }
        }.controlSize(.small)
      }
      if let directory = browser.directory {
        Text(directory.path).font(.system(size: 10)).foregroundStyle(.secondary)
          .lineLimit(1).truncationMode(.head).help(directory.path)
        TextField("Cerca per nome…", text: $browser.query)
          .textFieldStyle(.roundedBorder).font(.system(size: 11)).focused($searching)
        Picker("Cerca in", selection: $browser.searchSubfolders) {
          Text("Questa cartella").tag(false)
          Text("Sottocartelle · Spotlight").tag(true)
        }.pickerStyle(.segmented).controlSize(.small)
        ZStack(alignment: .topTrailing) {
          List(selection: $browser.selected) {
            ForEach(browser.files) { file in
              HStack(spacing: 7) {
                Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                  .foregroundStyle(file.isDirectory ? Color.accentColor : .secondary)
                  .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                  Text(file.name).lineLimit(1)
                  if !browser.query.isEmpty {
                    Text(file.url.deletingLastPathComponent().path).font(.system(size: 9))
                      .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                  }
                }
                Spacer(minLength: 0)
                if file.isDirectory {
                  Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
              }
              .font(.system(size: 11)).contentShape(Rectangle())
              .tag(file.url)
              .onTapGesture(count: 2) { browser.open(file) }
              .onDrag { NSItemProvider(object: file.url as NSURL) }
              .contextMenu {
                Button("Apri") { browser.open(file) }
                if !file.isDirectory {
                  Button("Anteprima") { FileBrowserPreview.shared.show(file.url) }
                }
                Button("Aggiungi alla Shelf") { shelf.add(url: file.url) }
                Button("Mostra in Finder") {
                  NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
              }
            }
          }
          .listStyle(.plain).scrollContentBackground(.hidden)
          .overlay {
            if browser.files.isEmpty && browser.message == nil && !browser.loading {
              Text(browser.query.isEmpty ? "Cartella vuota" : "Nessun risultato").font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .onKeyPress(.space) {
            guard let selected = browser.selected else { return .ignored }
            FileBrowserPreview.shared.show(selected)
            return .handled
          }
          .onKeyPress(.return) {
            guard let selected = browser.files.first(where: { $0.url == browser.selected }) else {
              return .ignored
            }
            browser.open(selected)
            return .handled
          }
          if browser.loading {
            ProgressView().controlSize(.small).padding(8).allowsHitTesting(false)
          }
        }
      } else {
        VStack(spacing: 10) {
          Image(systemName: "folder").font(.title)
          Text("I tuoi file, dentro l’Island").font(.headline)
          Button("Scegli una cartella…") { browser.chooseFolder() }
          Text("Aggiungi Download, Documenti o una cartella di lavoro.").font(.caption)
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let message = browser.message {
        Text(message).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
      }
      if let selected = browser.files.first(where: { $0.url == browser.selected }) {
        HStack {
          Button("Apri") { browser.open(selected) }
          Button("Anteprima") { FileBrowserPreview.shared.show(selected.url) }.disabled(
            selected.isDirectory)
          Button("Alla Shelf") { shelf.add(url: selected.url) }
        }.controlSize(.mini)
      }
    }
    .padding(.horizontal, 16).padding(.top, 8)
    .task {
      await Task.yield()
      guard !Task.isCancelled else { return }
      searching = true
      browser.activate(session: session)
    }
    .onDisappear {
      DispatchQueue.main.async { browser.deactivate(session: session) }
    }
  }
}

/// A separate window survives the Island's automatic mouse-exit collapse.
@MainActor
private final class FileBrowserPreview {
  static let shared = FileBrowserPreview()
  private var window: NSWindow?
  private var preview: QLPreviewView?

  func show(_ url: URL) {
    if window == nil {
      guard
        let preview = QLPreviewView(
          frame: NSRect(x: 0, y: 0, width: 640, height: 440), style: .normal)
      else { return }
      let window = NSWindow(
        contentRect: preview.frame,
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = preview
      window.center()
      self.preview = preview
      self.window = window
    }
    preview?.previewItem = url as NSURL
    window?.title = url.lastPathComponent
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
