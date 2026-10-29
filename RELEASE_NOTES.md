# OMP Korean 18.13.3-ko.3

**macOS Apple Silicon·Intel용 배포를 추가했습니다.** 기존 Windows 설치 방법과 실행 중 `/language ko`·`/language en` 언어 전환은 유지합니다.

이전 공개 버전 **18.13.3-ko.2**에서 기반 OMP 버전은 바뀌지 않았으며, macOS 빌드·설치·업데이트 지원과 세 플랫폼의 통합 배포 검증을 추가한 릴리즈입니다.

## 지원 환경

| 환경 | 배포 파일 |
|---|---|
| Windows x64 / PowerShell 5.1 이상 | `omp-korean-18.13.3-ko.3-windows-x64.zip` |
| macOS Apple Silicon | `omp-korean-18.13.3-ko.3-macos-arm64.tar.gz` |
| macOS Intel | `omp-korean-18.13.3-ko.3-macos-x64.tar.gz` |

기반 OMP **18.13.3**, Bun **1.4.4**입니다. 일반 사용자는 Bun·Node.js·Git을 별도로 설치할 필요가 없습니다. 기본 언어는 영어이며 `OMP_LANG=ko`로 한국어를 선택합니다.

## 주요 변경

- **macOS 설치기 추가:** `install.sh`가 Apple Silicon·Intel을 자동 구분해 해당 플랫폼 파일을 설치합니다.
- **사용자 환경 보존:** 기본 설치 경로는 `~/.local/share/omp-korean`, 실행 링크는 `~/.local/bin/omp`입니다. 셸 프로필·인증·설정·세션을 바꾸지 않으며 다른 `omp`가 링크 경로를 사용 중이면 덮어쓰지 않고 중단합니다.
- **설치 전 무결성 검사:** 플랫폼별 매니페스트·SHA-256·원시 ustar 헤더를 확인하고 경로 이탈·중복·링크·예상 밖 파일을 거부합니다. 실제 실행 파일의 영어·한국어 실행과 외부 언어팩 적용을 검사한 뒤 설치합니다.
- **재설치와 복원:** 기존 외부 언어팩을 보존하고, 파일 교체 실패 시 이전 상태로 복원합니다.
- **macOS 업데이트 지원:** 소스 빌드·업데이트에서 플랫폼별 실행 파일 이름과 실행 권한을 처리합니다. macOS 실행 파일은 원본 entitlements를 사용해 임시 서명합니다.
- **세 플랫폼을 함께 검증·게시:** Windows·macOS arm64·macOS x64의 실제 빌드와 설치 회귀 검사가 모두 성공해야 릴리즈를 게시합니다. Windows의 기존 `release.json`·`SHA256SUMS` 파일명은 유지하고 macOS는 아키텍처별 파일을 사용합니다.

## 설치

### Windows

```powershell
irm "https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.ps1" | iex
```

### macOS

```sh
curl -fL https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.sh -o install-omp-korean.sh
# 실행 전에 내려받은 스크립트 내용을 확인하세요.
bash install-omp-korean.sh
export PATH="$HOME/.local/bin:$PATH"
OMP_LANG=ko omp
```

위 PATH 설정은 현재 터미널에 적용합니다. 설치기는 셸 프로필을 자동 수정하지 않습니다. 다른 위치를 사용하려면 `OMP_INSTALL_DIR`·`OMP_BIN_DIR`에 절대 경로를 지정하세요.

ZIP 또는 tar.gz를 직접 풀어 사용할 수도 있습니다. 실행 파일과 `locales/`·`update/` 폴더를 함께 유지하세요. macOS에서는 `OMP_LANG=ko ./omp`로 실행합니다.

## 기존 사용자 안내

- 실행 중 언어 전환 `/language ko`·`/language en`과 저장된 현재 대화 재개를 유지합니다. 언어 선택은 영구 저장하지 않습니다.
- 기존 한국어팩을 수정했다면 재설치 시 그 파일을 보존합니다. 새 항목은 `update/locales/ko.json`과 비교·병합하세요.
- Windows의 설치 경로와 설치 명령은 같습니다. 실행 중인 OMP는 종료하고 다시 실행해야 새 실행 파일을 사용합니다.
- macOS 실행 파일은 임시 서명이며 개발자 인증서 서명·공증은 제공하지 않습니다. 보안 경고가 나오면 출처와 체크섬을 확인하세요.

## 검증 범위

- 제작 기록: Windows의 언어팩·업데이트·번역 재적용 대상 검사 65개 통과. 별도 스크립트 검사 152개 통과·기존 플랫폼 제외 9개·실패 0개.
- 제작 기록: 고정 원본의 전체 패치 적용, Windows 재빌드·양 언어 실행·외부 팩 검사, macOS 빌드 스크립트 타입·번들 검사, 셸 구문·워크플로 검사 통과.
- 이번 릴리즈의 실제 플랫폼별 빌드·설치 검사 결과는 [GitHub Actions](https://github.com/seojihun618-dotcom/omp-korean/actions/workflows/release.yml)에서 확인할 수 있습니다. 이 워크플로는 세 플랫폼 검사가 모두 성공해야 공개합니다.
- 전체 TypeScript/Rust 테스트를 이번 릴리즈에서 모두 다시 실행했다는 의미는 아닙니다.

플랫폼별 아카이브·체크섬·매니페스트와 `install.ps1`·`install.sh`는 아래 첨부 파일에서 받을 수 있습니다. 기존 릴리즈는 유지합니다.
