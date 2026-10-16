import SwiftUI

/// The main screen: mode at the top, live captions in the middle, one big button at the bottom.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showRecording = false
    @State private var showSetup = false
    @State private var showLarge = false
    @State private var showPlaceSheet = false

    private var mode: TranslationMode { model.settings.mode }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background

                VStack(spacing: 12) {
                    ModePicker()
                        .padding(.horizontal)
                        .padding(.top, 4)
                    StatusRow(showPlaceSheet: $showPlaceSheet, showSetup: $showSetup)
                    TranscriptList(pipeline: model.pipeline, mode: mode, showSetup: $showSetup)
                }

                ControlBar(showRecording: $showRecording, showLarge: $showLarge)
            }
            .navigationTitle("Thông Dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel(L.t("History", "Lịch sử"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if model.pipeline != nil && !model.isListening {
                            Button(role: .destructive) { model.clearTranscript() } label: {
                                Label(L.t("Clear screen", "Xóa màn hình"), systemImage: "eraser")
                            }
                        }
                        Button { textScale(+0.1) } label: { Label(L.t("Bigger text", "Chữ to hơn"), systemImage: "textformat.size.larger") }
                        Button { textScale(-0.1) } label: { Label(L.t("Smaller text", "Chữ nhỏ hơn"), systemImage: "textformat.size.smaller") }
                        Divider()
                        Button { showSettings = true } label: { Label(L.t("Settings", "Cài đặt"), systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showRecording) { RecordingView() }
            .sheet(isPresented: $showSetup) { SetupView() }
            .sheet(isPresented: $showPlaceSheet) { PlacePickerSheet() }
            .fullScreenCover(isPresented: $showLarge) { LargeTextView() }
            .alert(L.t("Something went wrong", "Có lỗi xảy ra"),
                   isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onChange(of: model.openedRecording) { _, url in
                if url != nil { showRecording = true }
            }
        }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            LinearGradient(
                colors: [Theme.accent(mode).opacity(0.18), Theme.accent(mode).opacity(0)],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.4), value: mode)
        }
    }

    private func textScale(_ delta: Double) {
        model.settings.textScale = min(2.0, max(0.8, model.settings.textScale + delta))
    }
}

// MARK: - Mode picker

struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TranslationMode.allCases) { m in
                let selected = model.settings.mode == m
                Button {
                    withAnimation(.snappy) { model.settings.mode = m }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: L.modeIcon(m))
                        Text(L.modeName(m)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background {
                        if selected {
                            Capsule().fill(Theme.gradient(m))
                                .shadow(color: Theme.accent(m).opacity(0.35), radius: 8, y: 3)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.sessionState != .idle)
            }
        }
        .padding(5)
        .background(Theme.card, in: Capsule())
        .opacity(model.sessionState == .idle ? 1 : 0.7)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Status chips

struct StatusRow: View {
    @Environment(AppModel.self) private var model
    @Binding var showPlaceSheet: Bool
    @Binding var showSetup: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                engineChip
                sceneChip
                placeChip
                translatorChip
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var engineChip: some View {
        let s = model.settings
        if s.engine == .appleLive && model.appleLiveInstalled.contains(s.appleLanguage) {
            Menu {
                ForEach(SpokenLanguage.allCases) { lang in
                    Button(L.languageName(lang)) { model.settings.appleLanguage = lang }
                        .disabled(!model.appleLiveInstalled.contains(lang))
                }
            } label: {
                Chip(icon: "waveform", text: "\(s.appleLanguage.badge) → VI", tint: Theme.accent(s.mode))
            }
            .disabled(model.sessionState != .idle)
        } else {
            Chip(icon: "waveform", text: "EN · ES → VI", tint: Theme.accent(s.mode))
        }
    }

    private var sceneChip: some View {
        Menu {
            ForEach(ListeningScene.allCases) { scene in
                Button {
                    model.settings.scene = scene
                } label: {
                    if model.settings.scene == scene {
                        Label(L.sceneName(scene), systemImage: "checkmark")
                    } else {
                        Text(L.sceneName(scene))
                    }
                }
            }
        } label: {
            let loud = model.settings.effectiveScene == .loudspeaker
            Chip(icon: loud ? "hifispeaker.2.fill" : "person.2.fill",
                 text: loud ? L.t("Loudspeaker", "Qua loa") : L.t("1-on-1", "Trực tiếp"))
        }
        .disabled(model.sessionState != .idle)
    }

    @ViewBuilder private var placeChip: some View {
        if model.settings.rememberLocation || model.currentRecord != nil {
            Button { showPlaceSheet = true } label: {
                if let name = model.currentPlaceName {
                    Chip(icon: "mappin.circle.fill", text: name, tint: .pink)
                } else if model.currentRecord != nil {
                    Chip(icon: "mappin.and.ellipse", text: L.t("Name this place", "Đặt tên nơi này"), tint: .pink)
                } else {
                    Chip(icon: "location", text: L.t("Place", "Địa điểm"))
                }
            }
            .buttonStyle(.plain)
            .disabled(model.currentRecord == nil)
        }
    }

    @ViewBuilder private var translatorChip: some View {
        switch model.translatorState {
        case .loading:
            Chip(icon: "hourglass", text: L.t("Loading translator…", "Đang nạp bộ dịch…"), tint: .orange)
        case .missing:
            Button { showSetup = true } label: {
                Chip(icon: "exclamationmark.triangle.fill", text: L.t("Add models", "Thêm mô hình"), tint: .orange)
            }.buttonStyle(.plain)
        case .failed:
            Button { showSetup = true } label: {
                Chip(icon: "exclamationmark.triangle.fill", text: L.t("Translator error", "Lỗi bộ dịch"), tint: .red)
            }.buttonStyle(.plain)
        case .ready:
            if let m = model.activeTranslator {
                Chip(icon: "cpu", text: m.displayName)
            }
        }
    }
}

// MARK: - Bottom controls

struct ControlBar: View {
    @Environment(AppModel.self) private var model
    @Binding var showRecording: Bool
    @Binding var showLarge: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                SideButton(icon: "waveform.badge.plus", label: L.t("Recording", "Bản ghi")) {
                    showRecording = true
                }
                .disabled(model.sessionState != .idle)

                Spacer()
                MicButton()
                Spacer()

                SideButton(icon: "textformat.size", label: L.t("Big text", "Chữ lớn")) {
                    showLarge = true
                }
            }
            .padding(.horizontal, 28)

            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: model.sessionState)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
        .ignoresSafeArea(edges: .bottom)
    }

    private var statusText: String {
        switch model.sessionState {
        case .idle: return L.t("Tap to start listening", "Nhấn để bắt đầu nghe")
        case .starting: return L.t("Starting…", "Đang khởi động…")
        case .listening:
            return model.settings.effectiveScene == .loudspeaker
                ? L.t("Listening to the loudspeaker…", "Đang nghe qua loa…")
                : L.t("Listening…", "Đang nghe…")
        case .stopping: return L.t("Finishing…", "Đang hoàn tất…")
        }
    }
}

private struct SideButton: View {
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(Theme.subtle, in: Circle())
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

struct MicButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let mode = model.settings.mode
        let listening = model.sessionState == .listening
        Button {
            model.toggleListening()
        } label: {
            ZStack {
                // Sound-level halo
                Circle()
                    .fill(Theme.accent(mode).opacity(0.22))
                    .frame(width: 96, height: 96)
                    .scaleEffect(listening ? 1 + CGFloat(model.level) * 0.45 : 1)
                    .animation(.easeOut(duration: 0.12), value: model.level)
                Circle()
                    .fill(listening ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Theme.gradient(mode)))
                    .frame(width: 80, height: 80)
                    .shadow(color: (listening ? Color.red : Theme.accent(mode)).opacity(0.4), radius: 10, y: 4)
                Group {
                    switch model.sessionState {
                    case .starting, .stopping:
                        ProgressView().tint(.white)
                    case .listening:
                        Image(systemName: "stop.fill").font(.system(size: 28, weight: .bold))
                    case .idle:
                        Image(systemName: "mic.fill").font(.system(size: 32, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(width: 100, height: 100)
        }
        .buttonStyle(.plain)
        .disabled(model.sessionState == .starting || model.sessionState == .stopping || model.fileJob?.isRunning == true)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.sessionState == .listening)
        .accessibilityLabel(listening ? L.t("Stop", "Dừng") : L.t("Start listening", "Bắt đầu nghe"))
    }
}
