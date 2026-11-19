# 틈 0.2.0

- 읽기 화면에서 더블클릭으로 문단을 선택하고 드래그로 필요한 부분만 복사할 수 있습니다. 연필 버튼이나 `⌘⇧M`으로 편집합니다.
- 본문과 편집기에 시스템 배경색과 글자색을 적용했습니다. 다섯 가지 메모 색은 가장자리 탭과 색상 선택기에 표시됩니다. 라이트·다크 모드는 macOS 설정을 따릅니다.
- 빈 메모의 안내 문구는 복사 대상에서 제외됩니다.
- Apple Silicon 및 macOS 14 이상에서 사용할 수 있습니다. 개발용 임시 서명 빌드이며 Apple 공증을 받지 않아 다른 Mac에서 최초 실행이 제한될 수 있습니다.

## Homebrew

```sh
brew tap willofi/teum-note https://github.com/willofi/teum-note.git
brew install --cask willofi/teum-note/teum
```

새 버전이 나오면 틈을 종료한 뒤 아래 명령으로 업데이트합니다. 기존 메모는 사용자 Application Support 폴더에 보관됩니다.

```sh
brew update
brew upgrade --cask willofi/teum-note/teum
```
