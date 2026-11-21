# 틈 0.5.0

- **최근 수정한 메모가 목록 아래에 모입니다.** 오래된 메모부터 표시하고, 새 메모와 최근 수정한 메모는 하단 `+` 바로 위에서 찾을 수 있습니다. 편집 중 자동 저장은 본문만 저장하며, 미리보기로 돌아가거나 메모를 닫거나 전환할 때 위치가 바뀝니다.
- **파일명으로 색을 자동 배정합니다.** 로컬과 연결 폴더의 메모에 같은 다섯 가지 색을 사용합니다. 탭과 열린 메모의 색이 일치하고, 정렬이 바뀌어도 색이 유지됩니다. 파일명을 바꾸면 색이 달라질 수 있습니다.
- **`⌘⇧M`으로 편집과 미리보기를 전환합니다.** 메모 창에 커서가 있거나 미리보기에서 텍스트를 선택한 상태에서도 사용할 수 있습니다.
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
