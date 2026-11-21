# 틈 0.3.0

- 가장자리 탭과 색상 선택기에 맑은 다섯 가지 색을 적용했습니다. 선택한 색을 메모 배경에도 옅게 반영하며, 라이트·다크 모드는 macOS 설정을 따릅니다.
- 메뉴 막대의 **틈 → 마크다운 폴더**에서 로컬 및 iCloud Drive 폴더를 여러 개 연결할 수 있습니다. 기존 메모를 Markdown 파일로 복사하면, 다른 Mac에서는 같은 폴더를 연결하고 iPhone에서는 **파일 → iCloud Drive**에서 확인할 수 있습니다.
- 연결 파일이 다른 곳에서 변경된 경우 덮어쓰기를 중단합니다. 저장하지 못한 편집은 별도 파일로 보존할 수 있습니다.
- 미리보기에서 문단 사이를 복사할 때 장식 구분선 문자가 포함되지 않습니다.
- Apple Silicon 및 macOS 14 이상을 지원합니다. 이 배포본은 임시 서명 빌드로, macOS에서 첫 실행 시 별도 승인이 필요할 수 있습니다.

## Homebrew

```sh
brew tap lee-jonny/teum-note https://github.com/lee-jonny/teum-note.git
brew install --cask lee-jonny/teum-note/teum
```

기존 `willofi/teum-note` 설치는 틈을 종료하고 위의 `brew tap`을 실행한 후 새 주소로 다시 설치합니다. 메모는 Application Support 폴더에 보관됩니다.

```sh
brew reinstall --cask lee-jonny/teum-note/teum
brew untap willofi/teum-note
```

전환 후에는 `brew update`와 `brew upgrade --cask lee-jonny/teum-note/teum`으로 업데이트합니다.
