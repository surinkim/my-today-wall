# MyTodayWall

<p align="center"><a href="README.md">English</a> | <b>한국어</b></p>

Bing 오늘의 이미지를 받아 연결된 모든 모니터의 배경화면으로 적용하는 macOS 메뉴바 앱. 공식 Bing Wallpaper 앱을 가볍게 대체하려고 만들었다.

- 앱을 시작하거나 새로 고침하면 최근 8일치 이미지를 4K(UHD)로 받아 두고, 최신 이미지를 자동으로 건다
- 이전/다음 버튼으로 받아 둔 이미지를 골라 바로 적용
- 사진 속 장소를 브라우저에서 바로 검색
- 모니터 연결·해제, 데스크톱(Space) 전환 때 자동으로 다시 적용
- 로그인 시 자동 시작, 오래된 이미지 자동 정리(기본 90일)

설계와 결정 사항은 [SPEC.md](SPEC.md)(영문)에 있다.

## 요구 사항

- macOS 15.0 (Sequoia) 이상
- Apple Silicon·Intel 겸용(유니버설) 빌드

## 설치

1. [Releases](https://github.com/surinkim/my-today-wall/releases)에서 `MyTodayWall.zip`을 받아 압축을 푼다
2. `MyTodayWall.app`을 응용 프로그램 폴더로 옮긴다. 로그인 항목은 `/Applications`에 있을 때만 자동 등록된다
3. 공증을 받지 않은 로컬 서명 앱이라 격리 표시를 지운다

   ```bash
   xattr -dr com.apple.quarantine /Applications/MyTodayWall.app
   ```

4. 실행한다. 첫 실행 때 로그인 항목에 등록되고 이미지를 받아 배경화면을 바꾼다

   ```bash
   open /Applications/MyTodayWall.app
   ```

공식 Bing Wallpaper 앱이 함께 돌면 배경화면을 서로 덮어쓰므로, 공식 앱은 삭제하거나 자동 시작을 끈다.

## 사용법

메뉴바의 사진 아이콘을 누르면 팝오버가 열린다.

| 항목 | 동작 |
| --- | --- |
| 썸네일 / `이 장소 검색` | 사진 속 장소의 Bing 검색 결과를 기본 브라우저로 연다 |
| `이전` / `다음` | 받아 둔 이미지를 날짜순으로 넘기며 바로 적용 |
| `새로 고침` | 새 이미지를 받고, 새 이미지가 나왔으면 최신 이미지로 바꾼다. 새 이미지가 없으면 지금 고른 이미지를 유지 |
| `로그인 시 자동 시작` | 시스템 설정 → 일반 → 로그인 항목과 같은 설정 |
| `보관 기간` | 30일 / 90일 / 180일 / 무제한. 지금 걸린 이미지는 기간이 지나도 지우지 않는다 |

- 이미지 지역은 시스템 언어·지역 설정을 따른다(예: `ko-KR`, `en-US`). Bing이 지원하지 않는 지역은 전 세계 공통 이미지가 온다
- Bing은 하루에 한 번 새 이미지를 올린다. ko-KR은 한국 시간 오후 4~5시쯤 바뀌므로 그 전에는 전날 이미지가 최신이다
- 앱은 시작할 때와 새로 고침을 누를 때만 확인한다. 잠자기에서 깨어나거나 자정이 지나도 저절로 바뀌지 않는다
- 화면 문구는 시스템 언어에 따라 영어 또는 한국어로 나온다

## 파일 위치

| 경로 | 내용 |
| --- | --- |
| `~/Pictures/MyTodayWall/` | 받은 이미지(`yyyyMMdd_이름.jpg`)와 `index.json`(목록, 현재 이미지) |
| `/Applications/MyTodayWall.app` | 앱 |

## 문제 해결

오류는 `os.Logger`(subsystem `kr.pe.corecode.MyTodayWall`)로 남는다. 로그 문구는 영어다. 지난 로그는 터미널에서 본다.

```bash
log show --last 1d --predicate 'subsystem == "kr.pe.corecode.MyTodayWall"' --style compact
```

실시간으로 보려면 Console.app에서 하위 시스템 `kr.pe.corecode.MyTodayWall`로 검색하고, 동작 → 정보 메시지 포함을 켠 뒤 시작을 누른다.

| 로그 | 원인 |
| --- | --- |
| `Failed to fetch Bing archive` | 네트워크 문제, 또는 방화벽이 bing.com을 막음 |
| `Failed to download image` | 이미지 파일 다운로드 실패 |
| `Failed to set wallpaper (모니터 이름)` | 해당 모니터에 적용 실패 |
| `Failed to register login item` | 로그인 항목 등록 실패 |

## 소스에서 빌드

Xcode 16 이상이 필요하다. 서드파티 의존성은 없다.

```bash
git clone https://github.com/surinkim/my-today-wall.git
```

```bash
cd my-today-wall && xcodebuild -project MyTodayWall.xcodeproj -scheme MyTodayWall -configuration Release -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

결과물은 `build/Build/Products/Release/MyTodayWall.app`이다. 기본 개발 도구가 Command Line Tools로 잡혀 있으면 명령 앞에 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 붙인다.

앱을 띄우지 않고 핵심 로직(받기·저장·자동 선택·이전/다음·보관 정책)만 실제 API로 확인하려면 아래 스크립트를 쓴다. 임시 폴더에서 돌고 배경화면은 바꾸지 않는다.

```bash
scripts/check-core.sh
```

## 제거

1. 팝오버에서 `로그인 시 자동 시작`을 끄고 `종료`를 누른다
2. `/Applications/MyTodayWall.app`을 휴지통으로 옮긴다
3. 받은 이미지까지 지우려면 `~/Pictures/MyTodayWall/` 폴더를 휴지통으로 옮긴다

## 참고

MyTodayWall은 문서화되지 않은 Bing 엔드포인트 `HPImageArchive.aspx`를 쓴다. 형식이 언제든 바뀔 수 있고, 그러면 앱을 고칠 때까지 동작하지 않을 수 있다.

이 저장소에는 앱 코드만 있고 Bing 이미지는 포함하지 않는다. 이미지는 각 사용자의 앱이 직접 받으며, 저작권은 각 사진작가와 에이전시에 있다. Bing 응답의 조건대로 개인 배경화면 용도로만 쓰고 재배포하지 않는다.

## 라이선스

[MIT](LICENSE)

## 고지

MyTodayWall은 개인이 만든 독립 프로젝트이며 Microsoft와 관계가 없고 Microsoft의 승인을 받지 않았다. Bing은 Microsoft Corporation의 상표다. 모든 이미지의 저작권은 각 저작권자에게 있다.
