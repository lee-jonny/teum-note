# 틈노트 개선안

2026년 11월 19일 기준. 첫 릴리스에서 확인할 사용자 흐름은 **기존 메모 열기 → 필요한 부분 복사 → 편집·저장 → 앱 업데이트 후 같은 메모 다시 열기**다.

## 1. 읽기와 편집

- **선택과 복사.** 한글, 이모지, 굵은 글씨와 줄바꿈을 포함한 문단을 더블클릭한 뒤 다른 앱에 붙여넣는다. 표시된 문단만 복사되어야 한다. 두 문단에 걸친 드래그와 코드 블록의 들여쓰기도 확인한다. 연필 버튼과 `⌘⇧M`으로 편집에 진입하고 빈 메모는 즉시 입력할 수 있게 한다. [미리보기](Sources/TeumApp/MarkdownPreview.swift) · [사용법](README.md)
- **편집부터 복구까지.** 한글을 조합하는 도중 서식·단축키가 입력을 가로채는지 확인한다. 메모 두 개로 탭 이동, 내용 편집 취소, 메모 삭제와 복원을 각각 실행한다. 마지막 변경 직후 패널을 닫고 앱을 다시 열어 본문·순서·색상을 확인한다. 임시 데이터 디렉터리에서 저장 실패도 재현해 사용자에게 오류가 보이는지 확인한다. [앱 명령 처리](Sources/TeumApp/AppController.swift) · [저장 처리](Sources/TeumApp/NotebookStore.swift)

## 2. 화면과 색상

Apple은 글자·배경·구분선에 용도에 맞는 시스템 색을 쓰고, 밝은 화면·어두운 화면·대비 증가 설정에서 확인하도록 권한다. Liquid Glass는 탐색과 조작에 쓰는 재질이다. 틈노트에는 **차분한 단색 본문과 작은 색상 탭**이 어울린다. 여러 앱 위에 떠 있는 패널에서도 글을 쉽게 읽고, 접힌 상태에서는 탭 색으로 메모를 찾을 수 있다. [Apple HIG 색상](https://developer.apple.com/design/human-interface-guidelines/color) · [Apple HIG 재질](https://developer.apple.com/design/human-interface-guidelines/materials)

- **본문과 도구.** 시스템의 배경색·기본 글자색·보조 글자색을 읽기와 편집에 함께 적용한다. 모드가 바뀌어도 본문과 커서가 선명해야 한다. 밝은 바탕과 어두운 바탕에서 같은 메모를 열어 링크·인용문·선택 영역·저장 오류를 확인한다. [읽기·편집 화면](Sources/TeumApp/NoteViews.swift) · [편집 서식](Sources/TeumCore/MarkdownEditingStyle.swift)
- **메모 식별.** 기존 다섯 색의 저장값을 유지하면서 색을 가장자리 탭과 색상 선택기에 집중한다. 선택한 색에는 체크나 윤곽을 함께 표시한다. 예전 버전의 메모를 열어 색 분류가 보존되는지, 색을 구분하기 어려운 상태에서도 현재 선택이 보이는지 확인한다. [메모 모델](Sources/TeumCore/Note.swift) · [Apple HIG 색상 접근성](https://developer.apple.com/design/human-interface-guidelines/color#Inclusive-color)

## 3. Homebrew 설치와 업데이트

기존 GitHub 저장소는 URL을 명시해 자체 탭으로 등록할 수 있다. Apple Silicon용 ZIP을 배포하는 틈에는 앱 번들을 설치하는 Cask가 맞는다. [Homebrew Taps](https://docs.brew.sh/Taps) · [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

1. **릴리스 생성.** 지정한 태그의 소스로 테스트하고 앱을 빌드한다. 번들의 버전, CPU 아키텍처, 최소 macOS 버전을 확인한다. 일반 공개 배포에서는 Developer ID로 서명한 앱을 공증하고 티켓을 첨부한 후 ZIP을 만든다. 다운로드할 최종 ZIP의 SHA-256을 계산한다. [릴리스 워크플로](.github/workflows/release.yml) · [Apple Developer ID와 공증](https://developer.apple.com/developer-id/)
2. **Cask 갱신.** 공개 ZIP을 내려받을 수 있는 시점에 탭의 버전과 해시를 함께 갱신한다. 앱 이름은 `Teum.app`, 배포 조건은 Apple Silicon과 macOS 14 이상으로 맞춘다. 재실행 시 동일 버전 URL의 내용이 바뀌면 이미 설치에 쓰인 해시와 어긋나므로 새 빌드에는 새 버전을 부여한다. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
3. **업데이트 검증.** 격리한 테스트 환경에서 이전 Cask로 설치하고 한글 메모를 만든 뒤 앱을 종료한다. 다음 버전을 게시한 후 `brew update`, `brew outdated --cask`, `brew upgrade --cask`로 해당 앱을 갱신한다. 번들의 새 버전과 기존 메모의 내용·순서·색상을 함께 확인하면 배포 검증이 끝난다. 실제 설치에 사용하는 탭 이름과 명령은 README에 한 곳으로 모은다. [Homebrew 명령 설명](https://docs.brew.sh/Manpage) · [프로젝트 README](README.md)

### Developer ID 서명과 공증

1. Apple Developer Program 팀의 Account Holder가 **Developer ID Application** 인증서를 발급하고, 배포용 Mac의 키체인에 인증서와 개인 키를 설치한다. `security find-identity -v -p codesigning`으로 서명 ID를 확인한다. [Developer ID 인증서 발급](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
2. 새 버전 태그의 소스에서 앱을 빌드한 뒤 아래 순서로 서명하고 공증한다. 먼저 Apple 계정의 앱 전용 암호로 `xcrun notarytool store-credentials teum-notary --apple-id "Apple 계정 이메일" --team-id "팀 ID"`를 실행해 공증 자격 증명을 키체인에 저장한다. [Apple 공증 워크플로](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

```sh
bash scripts/build-app.sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: 이름 (팀 ID)" dist/Teum.app
ditto -c -k --sequesterRsrc --keepParent dist/Teum.app dist/Teum-notary.zip
xcrun notarytool submit dist/Teum-notary.zip --keychain-profile teum-notary --wait
# 상태가 Accepted이면 티켓을 앱에 첨부한다.
xcrun stapler staple dist/Teum.app
xcrun stapler validate dist/Teum.app
spctl --assess --type execute --verbose=4 dist/Teum.app
```

3. 티켓이 첨부된 앱으로 버전 이름이 붙은 배포 ZIP을 다시 만들고, 새 GitHub Release를 공개할 때 함께 올린다. 릴리스 워크플로는 공개 ZIP을 다시 받아 번들 ID, 버전, 실행 파일, 아키텍처, 서명 무결성을 검사한 뒤 Cask에 해시를 반영한다. 서명과 공증을 CI에서 자동화하려면 배포 인증서와 공증 자격 증명을 GitHub Actions Secrets로 설정하고, ZIP을 게시하기 전에 `stapler validate`와 `spctl` 검사를 추가한다. [Apple 공증 워크플로](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
