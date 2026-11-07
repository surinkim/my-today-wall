import SwiftUI

struct MenuView: View {
    @ObservedObject var service: WallpaperService
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            details
            controls
            Divider()
            settings
            Divider()
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var thumbnail: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image = service.thumbnail {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 292, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: openSearch)
        .help(service.currentEntry == nil ? Text(verbatim: "") : Text("Search this place"))
    }

    private func openSearch() {
        guard let url = service.currentEntry?.searchURL else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var details: some View {
        if let entry = service.currentEntry {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.caption)
                    .font(.headline)
                    .lineLimit(2)
                Text([entry.date.bingDisplayDate, entry.credit].compactMap { $0 }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button(action: openSearch) {
                    Label("Search this place", systemImage: "magnifyingglass")
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.top, 2)
            }
        } else {
            (service.isRefreshing ? Text("Downloading images…") : Text("No images downloaded yet."))
                .foregroundStyle(.secondary)
        }
        if let message = service.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var controls: some View {
        HStack {
            Button { service.previous() } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!service.canGoPrevious)

            Button { service.next() } label: {
                HStack(spacing: 4) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
            }
            .disabled(!service.canGoNext)

            Spacer()

            Button {
                Task { await service.onLaunchOrRefresh() }
            } label: {
                if service.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(service.isRefreshing)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    LoginItem.setEnabled(on)
                    launchAtLogin = LoginItem.isEnabled
                }
            ))
            Picker("Keep images for", selection: $service.retentionDays) {
                ForEach(WallpaperService.retentionChoices, id: \.self) { days in
                    (days == 0 ? Text("Forever") : Text("\(days) days")).tag(days)
                }
            }
        }
    }
}
