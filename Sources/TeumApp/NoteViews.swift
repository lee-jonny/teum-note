import SwiftUI
import TeumCore

extension NoteColor {
    func surface(for scheme: ColorScheme) -> Color {
        let rgb: UInt32 = switch (self, scheme) {
        case (.butter, .dark): 0x38332F
        case (.peach, .dark): 0x383039
        case (.sage, .dark): 0x2D3834
        case (.sky, .dark): 0x2E3743
        case (.lavender, .dark): 0x35313F
        case (.butter, _): 0xFBEEE5
        case (.peach, _): 0xF9EAF1
        case (.sage, _): 0xE8F4ED
        case (.sky, _): 0xE8F2FC
        case (.lavender, _): 0xF2ECFC
        }
        return Color(.sRGB,
                     red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    var name: String {
        switch self {
        case .butter: "살구"
        case .peach: "로즈"
        case .sage: "민트"
        case .sky: "미스트 블루"
        case .lavender: "라일락"
        }
    }
}

private let ink = Color.primary

enum RailItem: Hashable {
    case note(UUID)
    case add
}

private struct RailFramesKey: PreferenceKey {
    static let defaultValue: [RailItem: CGRect] = [:]
    static func reduce(value: inout [RailItem: CGRect], nextValue: () -> [RailItem: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RailFrameReader: View {
    let item: RailItem
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: RailFramesKey.self, value: [item: geometry.frame(in: .named("rail"))])
        }
    }
}

struct EdgeRailView: View {
    @Bindable var store: NotebookStore
    let open: (UUID) -> Void
    let add: () -> Void
    let framesChanged: ([RailItem: CGRect]) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var alignment: HorizontalAlignment { store.notebook.edge == .right ? .trailing : .leading }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical) {
                VStack(alignment: alignment, spacing: 6) {
                    ForEach(store.notes) { note in
                        let selected = store.selectedID == note.id
                        let expanded = store.hoveredNoteID == note.id
                        Button { open(note.id) } label: {
                            Text(note.title)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: RailLayout.expandedWidth - 24, alignment: .leading)
                                .padding(.horizontal, 12)
                                .opacity(expanded ? 1 : 0)
                                .frame(width: expanded ? RailLayout.expandedWidth : RailLayout.collapsedWidth, height: 28)
                                .clipped()
                                .foregroundStyle(ink)
                                .background(note.color.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ink.opacity(selected ? 0.31 : 0.14)))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(note.title)
                        .accessibilityLabel("메모 열기: \(note.title)")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .frame(width: RailLayout.expandedWidth, height: 28, alignment: store.notebook.edge == .right ? .trailing : .leading)
                        .background(RailFrameReader(item: .note(note.id)))
                        .id(note.id)
                    }
                    Button(action: add) {
                        Image(systemName: store.loadFailed ? "exclamationmark.triangle" : "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(width: 18, height: 22)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(store.loadFailed ? "메모 파일 오류 확인" : "새 메모 · \(store.newNoteLocation)")
                    .accessibilityLabel(store.loadFailed ? "메모 파일 오류 확인" : "새 메모 · \(store.newNoteLocation)")
                    .background(RailFrameReader(item: .add))
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: store.notebook.edge == .right ? .trailing : .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: RailLayout.expandedWidth)
            .coordinateSpace(name: "rail")
            .onPreferenceChange(RailFramesKey.self, perform: framesChanged)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.hoveredNoteID)
            .onChange(of: store.scrollRequest) { _, request in
                guard let request else { return }
                scroll.scrollTo(request.noteID, anchor: .center)
            }
        }
    }
}

struct NoteEditorView: View {
    @Bindable var store: NotebookStore
    let close: () -> Void
    let add: () -> Void
    let delete: (UUID) -> Void
    let recover: () -> Void
    @State private var preview = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let note = store.selectedNote {
            let linkedFile = store.linkedFolders.file(for: note.id)
            VStack(spacing: 0) {
                Group {
                    if preview {
                        MarkdownPreview(source: note.text)
                            .id(note.id)
                            .overlay(alignment: .topLeading) {
                                if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("아직 적어둔 내용이 없어요.")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.top, 6)
                                        .allowsHitTesting(false)
                                }
                            }
                            .help("더블클릭으로 문단 선택 · 드래그로 부분 선택 · ⌘C로 복사")
                    } else {
                        editor(for: note)
                    }
                }
                .padding(.horizontal, 19).padding(.top, 24).padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(store.location(for: note.id))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 23)
                    .padding(.bottom, 3)

                HStack(spacing: 6) {
                    ForEach(linkedFile == nil ? NoteColor.allCases : [], id: \.self) { color in
                        Button { store.updateColor(color, id: note.id) } label: {
                            ZStack {
                                Circle().fill(color.surface(for: colorScheme))
                                    .overlay(Circle().strokeBorder(ink.opacity(0.26)))
                                    .frame(width: 12, height: 12)
                                if note.color == color {
                                    Circle().strokeBorder(ink.opacity(0.55)).frame(width: 17, height: 17)
                                }
                            }
                            .frame(width: 18, height: 26)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(color.name) 색상")
                        .accessibilityAddTraits(note.color == color ? [.isSelected] : [])
                        .help(color.name)
                    }
                    Spacer(minLength: 8)
                    Button {
                        if !preview { store.flush(finishingTitle: note.id) }
                        preview.toggle()
                    } label: {
                        Image(systemName: preview ? "pencil" : "eye")
                            .frame(width: 28, height: 28)
                            .background(preview ? ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .help(preview ? "메모 편집 · ⌘⇧M" : "마크다운 미리보기 · ⌘⇧M")
                    .accessibilityLabel(preview ? "메모 편집" : "마크다운 미리보기")
                    Menu {
                        Text(store.saveState(for: note.id))
                        Text("\(note.text.count)자")
                        if let linkedFile {
                            Text(linkedFile.deletingLastPathComponent().lastPathComponent)
                        }
                        if let file = store.file(for: note.id) {
                            Divider()
                            Button("Finder에서 파일 보기") {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                            }
                        }
                        Divider()
                        Button("메모 삭제…", role: .destructive) { delete(note.id) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 24, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("메모 옵션")
                    .accessibilityLabel("메모 옵션")
                    Button(action: add) {
                        Image(systemName: "plus").frame(width: 28, height: 28)
                    }
                    .help("새 메모 · \(store.newNoteLocation)")
                    .accessibilityLabel("새 메모")
                    Button(action: close) {
                        Image(systemName: store.notebook.edge == .right ? "arrow.right.to.line" : "arrow.left.to.line")
                            .frame(width: 28, height: 28)
                    }
                    .help("가장자리에 접기 · Esc")
                    .accessibilityLabel("메모 접기")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 23).padding(.bottom, 16)

                if store.saveFailed(for: note.id) {
                    HStack(spacing: 10) {
                        Text(store.saveState(for: note.id)).foregroundStyle(.red)
                        if store.canCopyDraft {
                            Button("편집 사본 저장", action: recover)
                        }
                    }
                    .font(.system(size: 11))
                    .padding(.bottom, 12)
                }
            }
            .foregroundStyle(ink)
            .buttonStyle(.plain)
            .background(note.color.surface(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor)))
            .onChange(of: note.id) { _, _ in
                preview = !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .onAppear { preview = !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else {
            VStack(spacing: 14) {
                Text("메모가 없습니다")
                    .font(.system(size: 15, weight: .medium))
                Button("새 메모 만들기", action: add)
                    .font(.system(size: 12))
                Text("⌘N으로 새 메모 · ⌘Z로 되돌리기")
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(ink)
            .buttonStyle(.plain)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func editor(for note: Note) -> some View {
        ZStack(alignment: .topLeading) {
            if note.text.isEmpty {
                Text("지금 떠오른 생각은?")
                    .font(.system(size: 16)).foregroundStyle(ink.opacity(0.35))
                    .padding(.horizontal, 5).padding(.top, 8)
                    .allowsHitTesting(false)
            }
            MarkdownEditor(text: Binding(
                get: { store.notes.first(where: { $0.id == note.id })?.text ?? "" },
                set: { store.updateText($0, id: note.id) }
            ))
            .id(note.id)
            .accessibilityLabel("메모 내용")
        }
    }
}
