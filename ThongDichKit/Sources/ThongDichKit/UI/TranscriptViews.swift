import SwiftUI

/// Scrolling list of translated lines, newest at the bottom, with live text underneath.
struct TranscriptList: View {
    @Environment(AppModel.self) private var model
    var pipeline: TranslationPipeline?
    var mode: TranslationMode
    @Binding var showSetup: Bool

    var body: some View {
        if let pipeline, !(pipeline.lines.isEmpty && pipeline.partial.isEmpty && model.sessionState == .idle) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(pipeline.lines) { line in
                            LineCard(line: line, mode: mode, scale: model.settings.textScale,
                                     showOriginal: model.settings.showOriginal)
                                .id(line.id)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                        if !pipeline.partial.isEmpty {
                            PartialCard(text: pipeline.partial, mode: mode)
                        } else if model.isListening && pipeline.lines.isEmpty {
                            ListeningPlaceholder(mode: mode)
                        }
                        Color.clear.frame(height: 170).id("bottom")
                    }
                    .padding(.horizontal)
                    .animation(.snappy, value: pipeline.lines.count)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: pipeline.lines.count) { _, _ in scrollDown(proxy) }
                .onChange(of: pipeline.lines.last?.vietnamese) { _, _ in scrollDown(proxy) }
                .onChange(of: pipeline.partial) { _, _ in scrollDown(proxy) }
                .onAppear { scrollDown(proxy, animated: false) }
            }
        } else {
            EmptyStateView(mode: mode, showSetup: $showSetup)
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

/// One translated line: Vietnamese big, the original small underneath.
struct LineCard: View {
    var line: TranscriptLine
    var mode: TranslationMode
    var scale: Double
    var showOriginal: Bool
    var showTime: Bool = false
    var timeText: String? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if line.kind == .prayer, let title = line.title {
                    HStack(spacing: 8) {
                        Image(systemName: "hands.and.sparkles.fill")
                        Text(title).font(.headline)
                        Spacer()
                        if let timeText { Text(timeText).font(.caption).foregroundStyle(Theme.secondaryText) }
                    }
                    .foregroundStyle(Theme.accent(.mass))
                    if line.vietnamese.isEmpty {
                        Text(L.t("The congregation prays together.", "Cộng đoàn cùng đọc kinh."))
                            .font(Theme.vietnameseFont(.mass, scale: scale * 0.8))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                if !line.vietnamese.isEmpty {
                    Text(line.vietnamese)
                        .font(Theme.vietnameseFont(mode, scale: line.kind == .prayer ? scale * 0.85 : scale))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if line.status == .translating || line.status == .waiting {
                    TranslatingIndicator(mode: mode)
                } else if line.status == .failed && line.kind != .prayer {
                    Text(L.t("Not translated", "Chưa dịch được"))
                        .font(.subheadline.italic())
                        .foregroundStyle(Theme.secondaryText)
                }

                if showOriginal && !(line.kind == .prayer && line.vietnamese.isEmpty == false && line.source.count > 220) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line.language.badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.subtle, in: Capsule())
                            .foregroundStyle(Theme.secondaryText)
                        Text(line.source)
                            .font(Theme.sourceFont(scale: scale))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(line.kind == .prayer ? 3 : nil)
                        Spacer(minLength: 0)
                        if let timeText, line.kind != .prayer {
                            Text(timeText).font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                if line.kind == .liturgy {
                    Chip(icon: "checkmark.seal.fill", text: L.t("Standard wording", "Lời chuẩn phụng vụ"), tint: Theme.accent(.mass))
                }
            }
        }
        .overlay {
            if line.kind == .prayer {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent(.mass).opacity(0.35), lineWidth: 1)
            }
        }
    }
}

struct TranslatingIndicator: View {
    var mode: TranslationMode
    @State private var phase = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.accent(mode))
                    .frame(width: 8, height: 8)
                    .opacity(phase ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: phase)
            }
            Text(L.t("Translating", "Đang dịch"))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .onAppear { phase = true }
    }
}

/// What is being said right now (not final yet).
struct PartialCard: View {
    var text: String
    var mode: TranslationMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.accent(mode))
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(text)
                .font(.body.italic())
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent(mode).opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

struct ListeningPlaceholder: View {
    var mode: TranslationMode

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "ear.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent(mode))
                .symbolEffect(.pulse, isActive: true)
            Text(L.t("Listening… translations appear here.", "Đang nghe… bản dịch sẽ hiện ở đây."))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Shown before the first session.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var model
    var mode: TranslationMode
    @Binding var showSetup: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 30)
                ZStack {
                    Circle().fill(Theme.accent(mode).opacity(0.14)).frame(width: 120, height: 120)
                    Image(systemName: L.modeIcon(mode))
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Theme.gradient(mode))
                }
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(L.modeHint(mode))
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if let progress = model.importProgress {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(Theme.accent(mode))
                        Text(L.t("Installing AI models… keep the app open", "Đang cài mô hình AI… hãy giữ ứng dụng mở"))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, 40)
                } else if model.needsSetup {
                    Button { showSetup = true } label: {
                        Label(L.t("Set up the AI models", "Cài đặt mô hình AI"), systemImage: "square.and.arrow.down.on.square")
                            .font(.headline)
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .background(Theme.gradient(mode), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }

                Label(L.t("Works offline · nothing leaves your iPhone", "Hoạt động ngoại tuyến · không gửi dữ liệu ra ngoài"),
                      systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 8)
                Spacer(minLength: 180)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var title: String {
        switch mode {
        case .everyday: return L.t("Talk naturally", "Trò chuyện tự nhiên")
        case .work: return L.t("Professional interpreting", "Thông dịch chuyên nghiệp")
        case .mass: return L.t("Follow the Mass in Vietnamese", "Theo dõi Thánh Lễ bằng tiếng Việt")
        }
    }
}
