# OMP Korean 19.2.1-ko.1

공식 OMP **19.2.1** 기반으로 갱신했습니다. 한국어 소스 업데이트 연결을 복원하고 Windows 스모크 종료 때 발생하던 임시 폴더 잠금 오류를 수정했습니다.

## 주요 변경

- 최신 CLI의 `const` worker 판정 구조를 지원합니다. worker 분기 뒤, 일반 UI 로딩 전에 언어팩을 초기화합니다.
- 관리 설치 보호·설치 잠금을 거쳐 한국어 소스를 업데이트합니다. 다운로드·빌드·검증에 실패하면 기존 설치본을 보존합니다.
- Windows의 임시 daemon 폴더 정리 중 `EBUSY`가 발생하면 최대 10초 동안 기다립니다. 이 처리는 구조가 일치하는 다음 소스 업데이트에도 적용됩니다.
- 영어·한국어 카탈로그는 **10,789개 항목**입니다. 기존 카탈로그 값은 유지했고, 새 원본과 일치하는 번역 위치 **4,936곳**을 재적용했습니다. 새 구조와 맞지 않는 곳은 영어로 표시되므로 이전 공개판보다 한국어 표시 범위가 줄어들 수 있습니다.
- HTML 내보내기는 공식 호스팅 뷰어와 무결성 정보를 사용합니다. npm 배포에는 외부 언어팩을 포함하며 네이티브 의존성의 라이선스 고지를 갱신했습니다.
- 공개 Windows 설치기의 일시적인 파일 공유 잠금 재시도와 실패 시 복원 동작을 유지합니다.

## 설치

Windows x64는 PowerShell 5.1 이상에서 실행하세요.

```powershell
irm "https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.ps1" | iex
```

macOS 설치기는 Apple Silicon과 Intel을 자동 구분합니다.

```sh
curl -fL https://github.com/seojihun618-dotcom/omp-korean/releases/latest/download/install.sh -o install-omp-korean.sh
bash install-omp-korean.sh
export PATH="$HOME/.local/bin:$PATH"
OMP_LANG=ko omp
```

ZIP·tar.gz를 직접 사용할 때는 실행 파일과 `locales/`·`update/` 폴더를 함께 두세요. 설치 후 버전은 `omp/19.2.1`로 표시됩니다.

기존 사용자 언어팩은 보존됩니다. 기본 영어·명시적 한국어 선택과 인증·설정·세션 보존 정책을 유지합니다. 실행 중인 OMP는 종료하고 다시 실행하세요.

## 검증 범위

- 배포 준비 기록에서 스크립트 67개와 언어·모델 원문·업데이트 경계 40개를 실행했고, 변경된 모듈 경로를 참조하던 3개 검사도 수정 후 통과했습니다.
- Windows 자식 프로세스가 임시 폴더를 사용하는 정리 회귀 검사, 공식 소스에 대한 패치 적용과 두 번째 재적용의 변경 파일 0개를 확인했습니다.
- 배포 준비 기록에서 실제 `omp update --force`로 소스 재적용·빌드·후보 실행·교체와 외부 언어팩 보존을 확인했습니다.
- 플랫폼별 빌드·설치·복원·언어팩 검사 결과는 [릴리즈 Actions](https://github.com/seojihun618-dotcom/omp-korean/actions/workflows/release.yml)에서 확인할 수 있습니다.
- 전체 TypeScript·Rust 검사와 실제 모델 요청은 이번 배포의 검증 범위에 포함되지 않았습니다.

[공식 원본 변경 비교](https://github.com/can1357/oh-my-pi/compare/f40f335845f0b136453d12fec8d6057011082766...b55cd1bb664d8ab46ddc77f2a34eb47555dbf1ac)
