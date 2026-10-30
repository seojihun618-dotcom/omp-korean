# OMP Korean — 한국어 언어팩 배포판

Windows x64 및 macOS Apple Silicon·Intel용 omp 언어팩 배포판입니다. **기본 실행은 영어**이며, `OMP_LANG=ko`로 한국어를 선택할 수 있습니다. 한국어 번역은 편집 가능한 외부 팩으로 제공합니다. 공식 omp가 언어팩을 읽는 것은 아니므로 **언어팩 지원 실행 파일을 함께 설치**합니다.

- 최신 배포: **[18.14.0-ko.1](https://github.com/seojihun618-dotcom/omp-korean/releases/tag/v18.14.0-ko.1)**
- 기반 omp: **18.14.0**
- 지원 대상: **Windows x64 / Windows PowerShell 5.1 이상**, **macOS arm64·x64**. macOS 실제 빌드·설치 성공 여부는 해당 릴리스의 Actions 결과를 확인하세요.
- 일반 사용자 실행: Bun·Node.js·Git 설치 불필요
- 원본 프로젝트: <https://github.com/can1357/oh-my-pi>

공식 프로젝트의 한국어 지원 릴리스가 아닌 별도 포크입니다. 모델 답변, 외부 도구 출력과 서비스 오류 원문까지 자동 번역하지는 않습니다.

최신 배포는 **18.14.0-ko.1**입니다. 아래 설치 명령은 GitHub Releases의 최신 공개 버전을 받습니다.

## 이번 버전의 주요 변경

**OMP 18.14.0 기반으로 갱신했습니다.** 일부 번역이 새 구조와 맞지 않아도 최신 원본 기능과 나머지 안전한 번역을 계속 적용합니다.

- 한국어 언어팩 **9,825개**: 이전 공개본보다 33개 항목을 추가했습니다.
- 명령 설명·브라우저 라벨의 언어 초기화 순서를 보완하고 업데이트 진행·결과 등의 번역을 보강했습니다.
- HTML 내보내기·통계·협업 화면은 각각 독립적으로 적용합니다. **18.14.0에서 바뀐 HTML 내보내기는 원본 화면을 유지해 일부 UI가 영어로 표시될 수 있습니다.**
- 잘못된 경로·기준과 실행 안전 오류는 교체 전에 중단하며, 기존 사용자 언어팩·인증·설정·세션 보존 정책은 유지합니다.
- Windows·macOS Apple Silicon·Intel을 지원합니다.

[전체 변경 사항·검증 범위](https://github.com/seojihun618-dotcom/omp-korean/releases/tag/v18.14.0-ko.1) · [최신 배포 파일](https://github.com/seojihun618-dotcom/omp-korean/releases/latest)

## 사용자가 설치하는 방법

### Windows: 터미널로 설치

아래 명령으로 최신 공개 배포 **18.14.0-ko.1**을 설치합니다.

```powershell
irm "https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.ps1" | iex
```

**Releases에 첨부된 install.ps1**에는 해당 저장소 주소가 들어 있으므로 추가 인수가 필요 없습니다. 원격 스크립트는 실행 전에 내용을 확인하고 신뢰할 수 있는 저장소의 주소만 사용하세요. 체크섬은 다운로드 손상을 검증하며 배포자의 신원을 보증하는 전자서명은 아닙니다.

설치기는 다음 작업만 수행합니다.

1. 공개 Releases에서 해당 버전 ZIP·매니페스트·체크섬 다운로드
2. SHA-256 및 ZIP 내부 파일 검증
3. 별도 폴더에 한글판 설치 및 실행 검증
4. 사용자 PATH에 추가하여 새 터미널의 `omp`가 한글판을 선택하도록 설정

기본 설치 경로는 `%LOCALAPPDATA%\omp-korean`입니다. 공식 `%LOCALAPPDATA%\omp` 실행 파일과 인증·설정·세션 데이터는 수정하지 않습니다. 기존 외부 `ko.json` 수정 사항도 유지합니다. 이 배포판은 공식판과 기존 사용자 데이터를 공유하므로 처음 사용하는 사람은 별도로 모델 인증이 필요합니다.

설치 후 터미널을 완전히 닫았다가 다시 열고 확인하세요.

```powershell
(Get-Command omp).Source
omp --version
omp --help
```

다른 PATH나 PowerShell 별칭이 우선한다면 직접 실행할 수 있습니다.

```powershell
& "$env:LOCALAPPDATA\omp-korean\omp.exe"
```

### Windows: ZIP으로 직접 사용

Releases에서 `omp-korean-18.14.0-ko.1-windows-x64.zip`을 내려받아 압축을 풀고, 해당 폴더에서 실행합니다.

```powershell
.\omp.exe
```

실행 파일과 `locales` 폴더를 함께 유지하세요. 관리자 권한은 필요하지 않습니다. 실행 파일은 서명되지 않았으므로 Windows 또는 보안 제품이 경고할 수 있습니다. 보안 기능을 해제하지 말고 배포 출처와 SHA-256을 확인하세요.

### macOS: 터미널로 설치

macOS용 설치기는 Apple Silicon은 `arm64`, Intel 맥은 `x64` 파일을 자동 선택합니다.

```sh
curl -fL https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.sh -o install-omp-korean.sh
# 실행 전에 내려받은 스크립트 내용을 확인하세요.
bash install-omp-korean.sh
export PATH="$HOME/.local/bin:$PATH"
command -v omp
OMP_LANG=ko omp
```

설치 폴더는 `~/.local/share/omp-korean`, 실행 링크는 `~/.local/bin/omp`입니다. 관리자 권한이 필요 없으며 셸 프로필·인증·설정·세션은 변경하지 않습니다. 다른 `omp`가 이미 해당 링크 경로를 사용하면 덮어쓰지 않고 중단합니다. PATH는 현재 터미널에서 직접 설정하며, 영구 적용하려면 사용하는 셸의 프로필을 직접 수정하세요.

다른 위치에는 `OMP_INSTALL_DIR`와 `OMP_BIN_DIR`를 절대 경로로 지정할 수 있습니다. 기존 한국어·영어 외부 팩은 재설치 시 그대로 보존합니다. 체크섬·아카이브 경로·파일 종류·실제 실행 검증을 통과한 파일만 설치합니다.

직접 실행하려면 Releases의 `omp-korean-18.14.0-ko.1-macos-arm64.tar.gz` 또는 `omp-korean-18.14.0-ko.1-macos-x64.tar.gz`를 별도 폴더에 풀고 `OMP_LANG=ko ./omp`를 실행하세요. `omp`, `locales/`, `update/`를 함께 유지하세요. macOS 빌드는 개발자 인증서·공증이 아닌 임시 서명을 사용합니다. Gatekeeper 경고 시 보안 기능을 해제하지 말고 배포 출처·체크섬을 확인하세요.

## 언어팩은 어떻게 적용되나요?

```text
설치 폴더/
├─ omp.exe             Windows (macOS는 omp)
├─ locales/
│  ├─ ko.json
│  └─ en.json
└─ update/             번역 기준·업데이트 도구·Bun 런타임
```

- 기본 언어는 영어입니다. `OMP_LANG` 미설정·빈 값·미지원 언어는 영어를 사용하며 언어팩을 읽지 않습니다.
- `OMP_LANG=ko` 또는 `ko-KR`을 명시하면 실행 파일 옆의 `locales/ko.json`을 비동기로 읽습니다.
- `ko.json`의 오른쪽 번역 문구만 수정하고 omp를 다시 실행하면 됩니다. 재빌드는 필요 없습니다.
- 선택한 한국어팩에 없는 항목은 영어 원문으로 표시합니다. 선택한 파일이 없거나 잘못되었으면 경고 후 영어로 실행합니다. 실행 파일에 숨겨진 내장 한국어팩은 없습니다.
- `en.json`은 영어 원문 참고 목록입니다. 영어 모드는 코드의 영어 원문을 사용합니다.
- 키와 `{0}`, `{1}` 같은 자리표시자, JSON 문법을 유지하세요. `\u0004` 뒤의 문맥은 같은 단어의 서로 다른 뜻을 구분합니다.
- 18.13.2-ko.4부터 파일·함수에 종속된 일부 문맥 키를 의미 기반으로 교체했습니다. 이전 `ko.json`은 자동으로 덮어쓰지 않으므로, `update/locales/ko.json`의 새 키를 본인 수정본에 비교·병합하세요. 이전 키를 조회하는 호환 별칭은 없습니다.
- `OMP_LOCALE_DIR`가 이미 설정돼 있으면 그 디렉터리의 언어팩을 우선합니다.
- 외부 팩을 읽거나 검증할 수 없으면 팩 내용을 출력하지 않고 경고한 뒤 영어로 실행합니다. SDK·worker의 공통 import만으로는 언어팩을 읽지 않습니다.
- 안전하게 일치하는 CLI 명령 설명과 브라우저의 테마·탐색·도구 라벨은 언어 초기화 뒤에 번역합니다. 독립 `omp-stats` 도움말에도 선택한 언어를 적용합니다. 18.14.0에서 구조가 바뀐 HTML 내보내기는 최신 원본을 유지하며, 이전 버전의 제목·컨트롤·접근성 이름 한글화는 재적용하지 않습니다. 대화·모델 응답·원시 도구 결과는 번역하지 않습니다.

실행 중에는 입력창에 다음 명령을 입력할 수 있습니다.

```text
/language ko
/language en
```

명령을 실행하면 OMP가 자동으로 재시작되며 저장된 현재 대화를 재개합니다. 시작할 때 지정한 실행 옵션도 유지합니다. `/language` 자동완성에서 `ko`·`en`을 선택할 수 있으며, 다른 값이나 추가 인수는 사용법만 표시합니다. 이 명령은 대화형 TUI용이며 모델 답변이나 과거 메시지를 번역하지 않습니다.

언어 선택은 재시작된 OMP 프로세스에 적용되며 사용자 환경변수나 설정 파일에는 저장하지 않습니다. OMP를 완전히 종료하고 새로 실행하면 터미널의 `OMP_LANG` 값 또는 기본 영어를 다시 사용합니다. 한국어팩을 읽을 수 없으면 기존과 같이 경고 후 영어로 실행합니다.

```powershell
$env:OMP_LANG = "en"  # 현재 터미널에서 영어 선택
omp
$env:OMP_LANG = "ko"  # 현재 터미널에서 한국어 선택
omp
Remove-Item Env:OMP_LANG -ErrorAction SilentlyContinue  # 기본 영어로 복귀
```

macOS에서 현재 터미널의 언어를 선택하려면 `OMP_LANG=ko omp` 또는 `OMP_LANG=en omp`를 사용합니다.

## 업데이트와 제거

`omp update --check`는 설치 버전과 최신 공식 안정 버전을 조회합니다. 설치 파일이나 사용자 데이터를 바꾸지 않습니다. **`omp update`는 최신 공식 소스를 별도 작업 폴더에 받아 기존 번역을 다시 연결하고 한글판을 빌드합니다.** 전체 한글화 패치를 Git으로 병합하거나 충돌 시 공식 영어판으로 전환하지 않습니다. 같은 버전이면 유지하고 더 이전 버전은 설치하지 않습니다.

이전 개발용 설치의 `omp-localized.json`이 있는 경로에는 배포 설치기가 덮어쓰지 않습니다. 그런 경우 Windows는 다른 `-InstallDir`, macOS는 다른 `OMP_INSTALL_DIR`를 사용하세요. 사용자 데이터 폴더를 삭제하거나 공식 설치 파일을 바꿔 해결하지 마세요.

번역은 이전에 검토된 문구와 사용 문맥이 안전하게 일치하는 곳에만 재적용합니다. **새 항목, 바뀐 문구·문맥, 모호한 위치는 최신 영어 원문으로 두고, 번역 불일치만으로 업데이트를 막지 않습니다.** 번역 키가 외부 `ko.json`에 없을 때도 영어 원문을 표시합니다.

HTML 내보내기·통계·협업 화면은 서로 독립된 한글화 묶음입니다. 어느 묶음의 구조가 호환되지 않으면 그 묶음의 호스트 초기화·지연 라벨·일반 번역 호출·자산을 함께 제외하고 최신 원본을 유지합니다. 일부 라벨만 번역하거나 이전 코드를 이식하지 않으며, 다른 묶음의 안전한 번역과 업데이트는 계속합니다. 명령 도움말 같은 별도 파일의 구조 변경은 해당 파일만 제외합니다. 업데이트가 표시하는 제외 수는 이전에 검토한 번역 위치 수이지 현재 화면의 미번역 문자열 수가 아닙니다.

번역 불일치와 실행 안전 오류는 구분합니다. 잘못된 재적용 기준·경로, CLI의 worker 분기·언어 초기화 경계, 업데이트의 관리 설치 보호, 기존 원본 런타임과의 충돌처럼 안전에 필수인 조건을 충족하지 못하면 교체 전에 중단합니다. 18.14.0의 호스팅 HTML 뷰어는 원본 매니페스트의 URL·무결성 해시를 유지하며, 한글화한 자산을 다시 생성해 공개 서버에 없는 파일을 참조하지 않습니다.

업데이트에는 인터넷 연결과 소스·의존성·빌드를 위한 추가 디스크 공간이 필요합니다. 포터블 배포에는 Bun을 포함하므로 Bun·Node.js·Git을 별도로 설치할 필요가 없습니다. 실행 파일 옆의 **`update` 폴더를 유지**하세요. 새 실행 파일의 버전, 한국어·영어 실행, 외부 언어팩 적용을 확인한 뒤 교체합니다. 다운로드·빌드·검증 실패 시 기존 한글판을 유지하며 공식 영어판을 대신 설치하지 않습니다. 이전 실행 파일 백업과 작업 소스는 설치 폴더에 남습니다.

외부 언어팩·인증·설정·세션은 보존합니다. 기존 사용자 번역은 설치기로 재설치할 때도 유지되므로 새 번역을 받으려면 본인 수정본을 백업하고 비교·병합하세요. 안정 채널만 지원합니다. 이 동작은 **18.13.1-ko.3부터** 제공하며, 그보다 이전 배포판 사용자는 현재 배포판의 설치기 또는 ZIP으로 먼저 교체해야 합니다. 향후 원본의 빌드·업데이트 구조가 호환되지 않으면 업데이트를 중단하고 기존 버전을 유지합니다.

제거하려면 omp를 종료하고 설치 폴더를 지운 뒤 Windows의 **환경 변수 → 사용자 Path**에서 해당 경로만 제거합니다. 공식 omp와 인증·세션 데이터는 그대로 남습니다.

macOS에서는 실행을 종료하고 본인이 설치한 `~/.local/bin/omp` 링크와 `~/.local/share/omp-korean` 폴더만 삭제하세요. 다른 위치로 설치했다면 해당 경로를 사용합니다. 인증·설정·세션 폴더는 삭제하지 마세요.

## 배포자가 GitHub에 올리는 방법

이 폴더는 저장소 파일과 릴리스 산출물을 구분합니다.

```text
README.md                    사용자·배포자 안내
RELEASE_NOTES.md             이번 배포의 변경 사항과 제한
release.json                 배포 버전·기반 소스 고정 정보
install.ps1                  검증·설치 스크립트 원본
install.sh                   macOS 검증·설치 스크립트 원본
LICENSE                     원본 MIT 라이선스
THIRD-PARTY-NOTICES.txt       원본 서드파티 고지
locales/                     편집 가능한 언어팩
source/omp-language-pack.patch  기반 소스에 적용할 전체 포크 패치
scripts/                     빌드·검증 도구
.github/workflows/release.yml 자동 릴리스 작업
.github/workflows/verify.yml  고정 소스 재구성·전체 검사·TS/Rust 테스트
release/                     Releases에 첨부할 ZIP·tar.gz·플랫폼별 매니페스트·체크섬 등, Git 추적 제외
build/                       재빌드 작업 폴더, Git 추적 제외
```

**`omp.exe`를 저장소에 직접 커밋하지 마세요.** GitHub 일반 Git의 단일 파일 제한보다 큽니다. `release/`는 `.gitignore`로 제외하고 ZIP을 Releases 첨부 파일로 배포합니다. 인증 파일, 세션, `omp-localized.json`, 실행 파일 백업, `node_modules`는 이 저장소에 넣지 않습니다.

### 권장: 태그로 자동 빌드·게시

1. 빈 GitHub 저장소를 만들고 이 폴더의 저장소 파일을 올립니다. `.github`와 `.gitignore`도 포함하세요.
2. GitHub Actions 사용을 허용합니다. Windows x64, macOS arm64, macOS x64의 기본 러너에서 각각 빌드·실행·설치를 검증합니다.
3. `release.json`과 같은 버전의 태그 **`v18.14.0-ko.1`**을 push합니다.
4. 세 빌드가 모두 통과해야 하나의 Release에 Windows ZIP·설치기·매니페스트·체크섬, macOS 두 아키텍처의 tar.gz·매니페스트·체크섬과 `install.sh`를 함께 게시합니다. 하나라도 실패하면 게시하지 않습니다.
5. 게시된 Releases의 설치 스크립트 URL을 사용자에게 안내합니다.

```powershell
# 배포용 저장소에서 실행하는 예시입니다.
git init
git add .
git commit -m "Publish Korean language-pack distribution"
git branch -M main
git remote add origin https://github.com/seojihun618-dotcom/omp-korean.git
git push -u origin main
git tag v18.14.0-ko.1
git push origin v18.14.0-ko.1
```

자동 게시에는 워크플로의 `contents: write` 권한이 필요합니다. 저장소·조직 정책이 이를 차단하면 권한 정책을 확인하세요. 개인 토큰이나 모델 API 키를 저장소에 넣을 필요는 없습니다.

이미 저장소를 만든 경우 변경 파일을 커밋·push한 뒤 Actions의 **Windows and macOS release → Run workflow**에서 태그를 비워 먼저 빌드만 검증할 수 있습니다. 성공한 각 작업의 Artifacts에서 패키지를 받으세요. 게시하려면 변경 커밋을 가리키는 새 버전 태그를 push합니다. 이 로컬 폴더의 변경만으로 원격 저장소나 기존 Release가 갱신되지는 않습니다.

### 로컬 재빌드 또는 수동 게시

재빌드에는 Windows x64, Git, Windows의 `tar.exe`와 **Bun 1.4.4**가 필요합니다. 고정된 기반 소스와 해당 버전의 네이티브 애드온을 가져와 빌드합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -Repository seojihun618-dotcom/omp-korean
```

macOS에서는 해당 아키텍처의 맥과 Bun 1.4.4, Git이 필요합니다. Rosetta에서 Intel 패키지를 대신 빌드하지 않습니다.

```sh
bun scripts/build-release-macos.ts --repository seojihun618-dotcom/omp-korean
```

macOS 산출물은 `omp-korean-<version>-macos-<arch>.tar.gz`, `release-macos-<arch>.json`, `SHA256SUMS-macos-<arch>`, 저장소 주소가 지정된 `install.sh`입니다. 두 아키텍처는 각 맥에서 빌드하고 한 Release에 함께 첨부합니다. `release.json`·`SHA256SUMS`는 기존 Windows 설치기 호환을 위해 Windows 전용 이름을 유지합니다.

결과물은 `release/`에 생성됩니다. 같은 폴더의 ZIP, `SHA256SUMS`, `release.json`, **저장소 주소가 지정된 `install.ps1`**을 하나의 GitHub Release에 함께 첨부하세요. 소스 원본 `install.ps1`이나 저장소가 지정되지 않은 초기 로컬 산출물은 온라인 설치 시 `-Repository seojihun618-dotcom/omp-korean`를 명시해야 합니다. GitHub Actions 또는 위 명령으로 생성한 주소 지정 스크립트를 게시하는 것이 가장 간단합니다.

```powershell
# 내려받은 설치 스크립트 원본을 명시적 저장소로 실행하는 예
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Repository seojihun618-dotcom/omp-korean
```

`-ExecutionPolicy Bypass`는 그 PowerShell 프로세스에만 적용합니다. 시스템 실행 정책이나 보안 기능을 영구적으로 바꾸지 않습니다.

번역만 바꿀 때는 `locales/ko.json`을 수정하세요. 새 배포에서는 `release.json`의 배포 버전과 ZIP 이름, 릴리스 노트를 함께 갱신하고 같은 버전의 태그를 만드세요. 배포자가 기반 omp를 올릴 때는 소스 패치와 빌드 호환성을 검증해야 합니다. 사용자 업데이트는 번역 기준을 최신 소스에 재적용하지만, 미래 버전의 구조 변경까지 자동 호환된다고 보장하지 않습니다.

## 라이선스

원본 omp의 MIT 라이선스와 저작권 표기를 `LICENSE`에 그대로 보존합니다. 서드파티 고지도 배포 파일에 포함합니다. 재배포할 때 해당 고지를 유지하세요. 이 저장소는 원본 프로젝트의 공식 배포나 보증을 의미하지 않습니다.
