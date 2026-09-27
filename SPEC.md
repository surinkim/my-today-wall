# Bing 배경화면 앱 개발 문서

## 개요

Bing 오늘의 이미지를 받아 로컬에 저장하고, 연결된 모든 모니터의 배경화면으로 적용하는 개인용 macOS 메뉴바 앱이다. 공식 Bing Wallpaper 앱 업데이트 후 버튼이 눌리지 않는 문제를 대체하는 것이 목적이다.

- 사용 범위: 본인 1인, 배경화면 용도 전용 (Bing 응답에 명시된 "wallpaper only" 조건 준수). 배포·재공유 없음
- 대상 OS: macOS Sequoia 15.5 이상
- 모니터 환경: 집 1대, 회사 듀얼. 연결 대수가 바뀌어도 자동으로 모든 화면에 적용

| 항목 | 값 |
| --- | --- |
| 앱 표시 이름 | MyTodayWall |
| Xcode 프로젝트·폴더 이름 | `MyTodayWall` |
| GitHub repo | `my-today-wall` (비공개) |
| Bundle ID | `kr.pe.corecode.MyTodayWall` |

## 기술 스택

Swift + SwiftUI 메뉴바 앱으로 만든다. 배경화면 설정, 모니터 목록, 로그인 항목 등록이 모두 AppKit 네이티브 API라서 Go로 하면 cgo나 AppleScript 우회가 필요하기 때문이다.

| 항목 | 선택 | 비고 |
| --- | --- | --- |
| 언어 / UI | Swift 5.10+, SwiftUI `MenuBarExtra` | Dock 아이콘 없음 (`LSUIElement = YES`) |
| 배경화면 적용 | `NSWorkspace.setDesktopImageURL(_:for:options:)` | 화면(`NSScreen`)별 호출 |
| 자동 시작 | `SMAppService.mainApp` | macOS 13+ 공식 로그인 항목 API |
| 네트워크 | `URLSession` + `async/await` | 외부 의존성 없음 |
| 저장 | 파일시스템 + `index.json` | DB 불필요 |
| 빌드 | Xcode 16, 로컬 서명(Sign to Run Locally) | 배포 안 하므로 공증 불필요 |

서드파티 패키지는 쓰지 않는다.

## 기능 요구사항

요청한 4가지 기능이 핵심이며, 모두 macOS 기본 API로 구현 가능하다.

| ID | 기능 | 동작 기준 |
| --- | --- | --- |
| F1 | 로그인 시 자동 시작 | 메뉴에서 켜고 끌 수 있고, 기본값은 켜짐 |
| F2 | 이미지 다운로드·로컬 저장 | 앱 시작·새로 고침 시 최근 8일치 중 없는 이미지만 UHD로 저장, 중복 다운로드 없음 |
| F3 | 이전 이미지 선택 | 이전/다음 버튼으로 저장된 이미지를 넘기며 즉시 적용, 새 이미지가 나온 뒤 시작·새로 고침하면 최신 이미지로 자동 선택 |
| F4 | 멀티 모니터 적용 | 연결된 모든 화면에 같은 이미지 적용, 모니터 연결·해제 시 자동 재적용 |

## 아키텍처

```
[메뉴바 UI]   [Scheduler(앱 시작)]   [ScreenObserver]
      \                |                 /
               [WallpaperService]
      /                |                 \
[BingClient]      [ImageStore]      [WallpaperApplier]
```

트리거(UI·스케줄·모니터 변경)는 모두 `WallpaperService`를 호출하고, 서비스가 받아오기·저장·적용을 순서대로 조율한다. 하위 모듈끼리는 서로 모른다.

## Bing API 연동

`HPImageArchive.aspx` 한 번 호출로 최근 8일치 메타데이터를 받는다. 비공식 엔드포인트라 형식이 바뀔 수 있으므로 파싱 실패는 조용히 넘기고 기존 이미지를 유지한다.

```
GET https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=ko-KR
```

| 파라미터 | 값 | 의미 |
| --- | --- | --- |
| `idx` | 0 | 오늘부터 (최대 7일 전까지) |
| `n` | 8 | 가져올 개수, 최대 8 |
| `mkt` | `ko-KR` | 지역. 한국판이 없는 날은 다른 지역 이미지가 올 수 있음 (2026-09-27 기준 `ROW` 이미지, `title`은 항상 "Info") |

| 응답 필드 | 용도 |
| --- | --- |
| `startdate` | 이미지 날짜(YYYYMMDD), 저장 키로 사용 |
| `urlbase` | 이미지 경로 앞부분. `https://www.bing.com` + `urlbase` + `_UHD.jpg` = 4K 원본 |
| `url` | 1920x1080 경로. UHD 실패 시 대체 |
| `title`, `copyright` | 메뉴 목록에 표시할 제목과 출처 |
| `hsh` | 이미지 해시, 중복 판정 |
| `wp` | 배경화면 사용 가능 여부. `false`면 건너뜀 |

응답 필드는 2026-09-27에 위와 같은 파라미터로 실제 호출해 확인했다 ([응답](https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=ko-KR), 8건 반환).

## 로컬 저장 구조

이미지는 날짜별 파일로, 목록과 현재 상태는 `index.json` 하나로 관리한다.

```
~/Pictures/MyTodayWall/
├── 20260927_MichelSunset.jpg
├── 20260926_Kirkjufell.jpg
├── ...
└── index.json
```

- 파일명: `startdate` + `_` + `urlbase`에서 `OHR.` 뒤 \~ `_` 앞 이름. 날짜순 정렬이 곧 파일명 정렬
- 저장 위치를 `~/Pictures`로 두는 이유: 샌드박스를 끄면 권한 문제 없이 접근 가능하고 Finder에서 바로 보인다
- 쓰기 순서: 임시 파일로 다운로드 → 완료 후 이름 변경(atomic) → `index.json` 갱신. 중간에 꺼져도 깨진 파일이 목록에 오르지 않음
- 보관 정책: 기본 90일 경과분 자동 삭제, 팝오버의 보관 기간 메뉴에서 변경(30일/90일/180일/무제한). 정리는 다운로드 직후에 실행하며, `current` 이미지는 기간이 지나도 삭제하지 않는다 (걸려 있는 배경화면 파일이 사라지지 않도록)

```json
{
  "current": "20260927",
  "lastAutoDate": "20260927",
  "images": [
    { "date": "20260927", "file": "20260927_MichelSunset.jpg",
      "title": "...", "copyright": "...", "hsh": "..." }
  ]
}
```

`current`는 지금 걸려 있는 이미지, `lastAutoDate`는 마지막으로 자동 선택한 최신 이미지의 날짜(`startdate`)다.

## 이전 이미지 선택

기본은 최신 이미지를 자동으로 걸고, 마음에 안 들면 이전/다음 버튼으로 바꾼다. 새 이미지가 나온 뒤 앱을 켜거나 새로 고침하면 다시 최신 이미지가 자동 선택된다.

"오늘"을 로컬 날짜로 판정하지 않는 이유: ko-KR 이미지는 매일 KST 16:00(UTC 07:00, `fullstartdate`)에 바뀌므로, 로컬 날짜와 `startdate`를 맞추면 오전에는 오늘 이미지가 없어 아무것도 적용되지 않는다. 그래서 "받아 둔 것 중 가장 최신 이미지"를 기준으로 한다.

메뉴바 팝오버 구성: 현재 이미지 썸네일 + 제목·날짜, `◀ 이전` · `다음 ▶` · `새로 고침` 버튼. 하단에 `로그인 시 자동 시작` 토글, `보관 기간` 선택, `종료` 버튼.

1. **앱 시작 / 새로 고침**: 새 이미지를 받아온 뒤, 최신 이미지 날짜가 `lastAutoDate`와 다르면 최신 이미지를 전 화면에 적용하고 `lastAutoDate = 최신 이미지 날짜`
2. **새 이미지 없이 다시 새로 고침**: 최신 이미지가 `lastAutoDate`와 같으므로 사용자가 고른 이미지를 그대로 유지
3. **이전 / 다음**: 저장된 이미지를 날짜순으로 한 장씩 넘기며 즉시 적용, `current`만 갱신해 `index.json`에 저장. 가장 오래된 것·가장 최신 것에서는 해당 버튼 비활성 (오늘 이미지를 받지 못한 날은 최신 저장본이 끝)

```swift
func onLaunchOrRefresh() async {
    await fetchAndStoreNew()
    if let latest = index.images.last, index.lastAutoDate != latest.date {
        select(latest)  // 전 화면 적용 + current 갱신
        index.lastAutoDate = latest.date
    }
    removeExpired()
    save()  // index.json 갱신
}
```

## 멀티 모니터 적용

집(1대)·회사(2대) 구분 없이 `NSScreen.screens` 전체를 돌며 적용하므로 별도 설정이 필요 없다.

```swift
func apply(_ url: URL) {
    let opts: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true
    ]
    for screen in NSScreen.screens {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: opts)
    }
}
```

재적용 시점은 두 가지다.

- 모니터 연결·해제: `NSApplication.didChangeScreenParametersNotification` 수신 시 현재 이미지 재적용 (노트북을 회사 모니터에 꽂는 순간)
- 데스크톱(Spaces) 전환: `NSWorkspace.activeSpaceDidChangeNotification` 수신 시, 화면별 `NSWorkspace.shared.desktopImageURL(for:)`가 목표 이미지와 다를 때만 재적용

주의할 제약: `setDesktopImageURL`은 각 화면의 **현재 Space에만** 적용된다. 데스크톱을 여러 개 쓰면 다른 Space는 전환해야 바뀌므로 위의 Space 전환 감지가 필요하다. 또한 같은 경로의 파일을 덮어쓰면 macOS가 캐시 때문에 갱신하지 않을 수 있어, 이미지마다 파일명을 다르게 둔 저장 구조가 이 문제도 피한다.

## 로그인 시 자동 시작

`SMAppService.mainApp` 등록 한 줄로 끝나며, LaunchAgent plist를 직접 만들 필요가 없다.

```swift
import ServiceManagement

func setLaunchAtLogin(_ on: Bool) throws {
    if on { try SMAppService.mainApp.register() }
    else  { try SMAppService.mainApp.unregister() }
}
// 메뉴 토글 표시값: SMAppService.mainApp.status == .enabled

// 기본값 "켜짐": 첫 실행에 한 번만 등록한다
func registerOnFirstLaunch() {
    let key = "didInitialLoginItemSetup"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    try? setLaunchAtLogin(true)
    UserDefaults.standard.set(true, forKey: key)
}
```

- 매 실행마다 `register()`를 호출하면 사용자가 시스템 설정에서 끈 것이 다시 켜지므로, 최초 1회만 등록하고 이후에는 사용자의 선택을 따른다
- 앱은 `/Applications`에 두어야 등록이 안정적이다 (Xcode 빌드 폴더에서 등록하면 경로가 바뀔 때 풀림)
- 등록 후 시스템 설정 → 일반 → 로그인 항목에 표시된다. 사용자가 거기서 끄면 `status`가 바뀌므로 토글 표시는 매번 `status`에서 읽는다

## 스케줄링·에러 처리·주의사항

갱신은 "목록에 없는 이미지만 받고, 최신 이미지가 바뀌었을 때만 자동 선택"이라는 멱등 동작으로 단순화한다. 새 이미지가 없으면 JSON 한 번 호출로 끝난다.

| 트리거 | 동작 |
| --- | --- |
| 앱 시작 (로그인 시 자동 시작 포함) | 새 이미지 체크 후 필요하면 자동 선택 |
| 새로 고침 버튼 | 같은 동작을 수동으로 실행 |

잠자기 해제·자정·주기 타이머 트리거는 의도적으로 두지 않는다. 회사 Mac은 일주일에 한 번만 재시작하므로 그 사이에는 원할 때 새로 고침 버튼으로 바꾼다.

| 상황 | 처리 |
| --- | --- |
| 네트워크 실패 | 현재 배경 유지, 다음 체크에서 재시도 |
| UHD 이미지 404 | `url`의 1920x1080으로 대체 |
| `wp = false` | 해당 이미지 건너뜀 |
| JSON 형식 변경 | 파싱 실패 로그만 남기고 기존 이미지 유지 |

- App Sandbox는 끈다. 켜면 `~/Pictures` 접근과 배경화면 적용에 entitlement·권한 처리가 추가로 필요한데, 개인용이라 이점이 없다
- 로그는 `os.Logger`(subsystem `kr.pe.corecode.MyTodayWall`)로 남겨 Console.app에서 확인
- 빌드: Xcode 16.4. 기본 개발 도구가 Command Line Tools로 잡혀 있으면 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 붙여 `xcodebuild`를 실행한다
- 1단계 확인: `scripts/check-core.sh`가 임시 폴더에서 실제 API로 받기·자동 선택·이전/다음·보관 정책을 돌려 본다 (배경화면은 바꾸지 않음)

## 구현 순서

단계마다 실제로 쓸 수 있는 상태를 만들며 진행한다. 2단계까지만 해도 공식 앱을 대체할 수 있다.

- [x] 1\. `BingClient` + `ImageStore`: 호출·다운로드·저장·`index.json`, 커맨드라인에서 동작 확인
- [x] 2\. `WallpaperApplier` + 메뉴바 앱 골격: 오늘 이미지를 모든 화면에 적용 (여기서 공식 앱 대체 가능)
- [x] 3\. 시작 시 체크 + 새로 고침 버튼, `lastAutoDate` 자동 선택 로직
- [x] 4\. 자동 시작 토글 (`SMAppService`, 첫 실행 1회 등록), `/Applications` 설치
- [x] 5\. 이전/다음 버튼 팝오버
- [ ] 6\. `ScreenObserver`: 모니터 연결·Space 전환 재적용, 회사 듀얼 환경에서 검증
- [x] 7\. 보관 정책: 오래된 파일 정리(`current` 제외), 보관 기간 메뉴
