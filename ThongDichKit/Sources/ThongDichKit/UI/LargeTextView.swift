import SwiftUI

/// Big-text display for reading at a distance (in church, at a meeting table, for elders).
/// Shows only the Vietnamese, newest line largest.
struct LargeTextView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mode = model.settings.mode
        let lines = Array((model.pipeline?.lines ?? []).filter { !$0.vietnamese.isEmpty || $0.kind == .prayer }.suffix(4))
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Chip(icon: L.modeIcon(mode), text: L.modeName(mode), tint: Theme.accent(mode))
                    if model.isListening {
                        Chip(icon: "record.circle", text: L.t("Live", "Trực tiếp"), tint: .red)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(Theme.subtle, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Close", "Đóng"))
                }
                .padding()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if lines.isEmpty {
                                Text(model.isListening
                                     ? L.t("Listening…", "Đang nghe…")
                                     : L.t("Start listening to see the translation here.", "Bắt đầu nghe để xem bản dịch ở đây."))
                                    .font(Theme.vietnameseFont(mode, scale: model.settings.textScale, large: true))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                let newest = index == lines.count - 1
                                VStack(alignment: .leading, spacing: 6) {
                                    if let title = line.title {
                                        Text(title)
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(Theme.accent(.mass))
                                    }
                                    if !line.vietnamese.isEmpty {
                                        Text(line.vietnamese)
                                            .font(Theme.vietnameseFont(mode, scale: model.settings.textScale * (newest ? 1 : 0.72), large: true))
                                            .foregroundStyle(newest ? Color.primary : Theme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .id(line.id)
                            }
                            Color.clear.frame(height: 30).id("end")
                        }
                        .padding(.horizontal, 22)
                        .animation(.easeInOut(duration: 0.3), value: lines.map(\.id))
                    }
                    .onChange(of: lines.last?.vietnamese) { _, _ in
                        withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }

                if model.sessionState == .listening || model.sessionState == .idle {
                    HStack {
                        Spacer()
                        MicButton().scaleEffect(0.8)
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
