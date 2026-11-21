# 틈 0.4.0

- **메모 하나당 Markdown 파일 하나.** 이전 로컬 메모는 개별 `.md` 파일로 전환하고 `notes.json` 원본은 백업으로 남깁니다. 파일명은 첫 줄 제목을 따르며 중복 이름에는 번호를 붙입니다.
- **iCloud Drive를 새 메모 저장 위치로 지정.** 메뉴 막대의 **틈 → 마크다운 폴더 → 새 메모 저장 폴더 선택…**에서 폴더를 고르면 `+`나 `⌘N`으로 만든 메모가 바로 그 폴더에 생깁니다. **이 Mac의 메모 폴더 열기**에서 로컬 파일도 확인할 수 있습니다.
- **메모별 저장과 복구.** 파일 충돌이 생겨도 다른 메모를 저장할 수 있습니다. 현재 편집을 로컬 사본으로 보관하고, 로컬·연결 메모의 생성과 삭제를 같은 실행 취소 기록에서 되돌릴 수 있습니다. 이미 복사한 메모는 같은 폴더에 다시 복사할 때 건너뜁니다.
- **더 옅은 색상.** 접힌 탭과 열린 메모에 같은 색을 적용합니다. 열린 메모에는 저장 위치, 새 메모 버튼에는 생성 위치를 표시합니다.
- Apple Silicon 및 macOS 14 이상을 지원합니다. 이 배포본은 임시 서명 빌드이며 macOS에서 첫 실행 시 별도 승인이 필요할 수 있습니다.

## Homebrew 업데이트

틈을 종료하고 실행합니다.

```sh
brew update
brew upgrade --cask lee-jonny/teum-note/teum
```

처음 설치하는 Mac에서는 다음 명령을 실행합니다.

```sh
brew tap lee-jonny/teum-note https://github.com/lee-jonny/teum-note.git
brew install --cask lee-jonny/teum-note/teum
```
