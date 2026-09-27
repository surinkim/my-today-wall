import Foundation
import ServiceManagement

enum LoginItem {
    private static let initialSetupKey = "didInitialLoginItemSetup"

    /// 시스템 설정에서 끌 수도 있으므로 매번 `status`에서 읽는다.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("로그인 항목 \(on ? "등록" : "해제", privacy: .public) 실패: \(error.localizedDescription, privacy: .public)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// 기본값 "켜짐": 처음 실행될 때 한 번만 등록하고, 이후에는 사용자의 선택을 따른다.
    /// 빌드 폴더에서 등록하면 경로가 바뀔 때 풀리므로 `/Applications`에 설치된 상태에서만 등록한다.
    static func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: initialSetupKey) else { return }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            Log.app.info("/Applications 밖에서 실행 중이라 로그인 항목 자동 등록을 미룬다")
            return
        }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: initialSetupKey)
    }
}
