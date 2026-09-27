import Foundation

// 1단계 확인용 커맨드라인 도구. 실제 Bing API로 받기·저장·index.json·자동 선택·보관 정책을 돌려 보고,
// 배경화면 적용은 출력으로 대신한다. 실행: scripts/check-core.sh [저장 폴더]

struct PrintApplier: WallpaperApplying {
    func apply(_ url: URL) { print("   → 적용: \(url.lastPathComponent)") }
    func applyWhereDifferent(_ url: URL) { print("   → 다른 화면만 적용: \(url.lastPathComponent)") }
}

let directory = URL(filePath: CommandLine.arguments.dropFirst().first!, directoryHint: .isDirectory)
let suite = "kr.pe.corecode.MyTodayWall.corecheck"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)

@MainActor
func report(_ service: WallpaperService) {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
        .filter { $0.hasSuffix(".jpg") }.sorted() ?? []
    print("   current=\(service.index.current ?? "-") lastAutoDate=\(service.index.lastAutoDate ?? "-")"
        + " 목록 \(service.index.images.count)건, 파일 \(files.count)개"
        + " 이전=\(service.canGoPrevious) 다음=\(service.canGoNext)"
        + (service.errorMessage.map { " 오류=\($0)" } ?? ""))
}

Task { @MainActor in
    print("저장 폴더: \(directory.path)")
    let service = WallpaperService(store: ImageStore(directory: directory), applier: PrintApplier(), defaults: defaults)

    print("1) 앱 시작: 받기 + 최신 이미지 자동 선택")
    await service.onLaunchOrRefresh()
    report(service)

    print("2) 다시 새로 고침: 다운로드·적용 없어야 함")
    await service.onLaunchOrRefresh()
    report(service)

    print("3) 이전 → 이전 → 다음")
    service.previous(); service.previous(); service.next()
    report(service)

    print("4) 새로 고침해도 고른 이미지 유지")
    await service.onLaunchOrRefresh()
    report(service)

    print("5) 앱 재시작(index.json 다시 읽기)")
    let restarted = WallpaperService(store: ImageStore(directory: directory), applier: PrintApplier(), defaults: defaults)
    report(restarted)

    print("6) 가장 오래된 이미지로 이동 후 보관 기간 3일: 오래된 파일은 지우고 current는 남아야 함")
    while restarted.canGoPrevious { restarted.previous() }
    restarted.retentionDays = 3
    report(restarted)

    defaults.removePersistentDomain(forName: suite)
    exit(0)
}
dispatchMain()
