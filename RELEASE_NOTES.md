# OMP Korean 19.0.1-ko.1

공식 OMP **19.0.1**을 기반으로 갱신했습니다. 재시작 코드가 바뀐 버전에서 멈추던 `omp update`를 수정하고, npm 배포에 외부 한국어팩을 다시 포함했습니다.

## 주요 변경

- 최신 OMP의 재시작 인수·환경 변수 전달 방식을 적용합니다. 이전 번역 보정과 맞지 않는 재시작 코드는 최신 원본을 사용하며, 일치하는 다른 번역은 계속 적용합니다.
- 영어·한국어 카탈로그는 각각 **10,789개**입니다. 이전 공개판 18.18.3-ko.1 대비 새 항목 258개를 추가하고 이전 도움말 키 1개를 교체했습니다. 계획 검토·모델 선택·대화 되감기·폼 메모와 분석·음성 설정 등의 문구를 보강했습니다.
- npm 번들은 동봉된 외부 한국어팩을 읽습니다. npm·표준 바이너리 빌드는 현재 소스에서 내장 HTML 뷰어를 생성하며 공식 호스팅 매니페스트를 보존합니다.
- 기본 언어는 영어입니다. `OMP_LANG=ko`로 한국어를 선택할 수 있습니다. 설치기는 기존 외부 언어팩을 보존하므로 사용자 팩에 새 번역을 추가하려면 `update/locales/ko.json`과 비교해 병합하세요.
- 구조가 달라진 화면은 일부 영어로 표시될 수 있습니다. 이번 소스에서 번역을 재적용한 위치는 9,051곳이며, 이 수치는 카탈로그 항목 수와 별개입니다.

## 설치

Windows x64는 PowerShell 5.1 이상에서 아래 명령을 실행하세요.

```powershell
irm "https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.ps1" | iex
```

macOS 설치기는 Apple Silicon과 Intel을 자동으로 구분합니다.

```sh
curl -fL https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.sh -o install-omp-korean.sh
bash install-omp-korean.sh
export PATH="$HOME/.local/bin:$PATH"
OMP_LANG=ko omp
```

첨부된 ZIP 또는 tar.gz를 직접 사용할 때는 실행 파일과 `locales/`, `update/`를 함께 두세요. `omp --version`에는 기반 버전인 `omp/19.0.1`이 표시됩니다.

## 검증

- 배포 준비 기록에서 Windows의 18.22.2 → 19.0.1 실제 업데이트와 19.0.1 강제 재빌드, 기존 언어팩 보존, npm 동봉 언어팩 사용을 확인했습니다.
- 공식 19.0.1 소스에 전체 패치를 적용했고, 같은 번역 기준을 두 번 적용했을 때 두 번째 실행에서 변경된 파일이 없었습니다.
- 플랫폼별 빌드와 설치·복원 검사 결과는 [릴리즈 Actions](https://github.com/seojihun618-dotcom/omp-korean/actions/workflows/release.yml)에서 확인할 수 있습니다.

[공식 원본 변경 비교](https://github.com/can1357/oh-my-pi/compare/21f1188cf88b2f534c092181968cd5a4d1a9c296...f40f335845f0b136453d12fec8d6057011082766)
