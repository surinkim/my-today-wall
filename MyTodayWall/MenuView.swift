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
                Button("종료") { NSApp.terminate(nil) }
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
        .help(service.currentEntry == nil ? "" : "이 장소 검색")
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
                    Label("이 장소 검색", systemImage: "magnifyingglass")
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.top, 2)
            }
        } else {
            Text(service.isRefreshing ? "이미지를 받는 중입니다." : "아직 받은 이미지가 없습니다.")
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
                Label("이전", systemImage: "chevron.left")
            }
            .disabled(!service.canGoPrevious)

            Button { service.next() } label: {
                HStack(spacing: 4) {
                    Text("다음")
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
                    Label("새로 고침", systemImage: "arrow.clockwise")
                }
            }
            .disabled(service.isRefreshing)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("로그인 시 자동 시작", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    LoginItem.setEnabled(on)
                    launchAtLogin = LoginItem.isEnabled
                }
            ))
            Picker("보관 기간", selection: $service.retentionDays) {
                ForEach(WallpaperService.retentionChoices, id: \.self) { days in
                    Text(days == 0 ? "무제한" : "\(days)일").tag(days)
                }
            }
        }
    }
}
