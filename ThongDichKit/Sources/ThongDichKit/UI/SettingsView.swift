import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showSetup = false
    @State private var confirmDeleteHistory = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                // Translation style
                Section {
                    Picker(L.t("Mode", "Chế độ"), selection: $model.settings.mode) {
                        ForEach(TranslationMode.allCases) { Text(L.modeName($0)).tag($0) }
                    }
                    Picker(L.t("How people are addressed", "Cách xưng hô"), selection: $model.settings.pronouns) {
                        ForEach(PronounStyle.allCases) { Text(L.pronounName($0)).tag($0) }
                    }
                    Picker(L.t("Vietnamese vocabulary", "Từ vựng tiếng Việt"), selection: $model.settings.dialect) {
                        ForEach(Dialect.allCases) { Text(L.dialectName($0)).tag($0) }
                    }
                    Picker(L.t("Work field", "Lĩnh vực công việc"), selection: $model.settings.workField) {
                        ForEach(WorkField.allCases) { Text(L.fieldName($0)).tag($0) }
                    }
                    NavigationLink {
                        GlossaryView()
                    } label: {
                        LabeledContent(L.t("My terms (glossary)", "Thuật ngữ riêng"), value: "\(model.settings.glossary.count)")
                    }
                } header: {
                    Text(L.t("Translation", "Dịch"))
                } footer: {
                    Text(L.t("Address forms apply to Everyday mode; the work field to Work mode. Mass mode always uses Catholic wording.",
                             "Cách xưng hô dùng cho chế độ Đời thường; lĩnh vực dùng cho chế độ Công việc. Chế độ Thánh Lễ luôn dùng từ ngữ Công giáo."))
                }

                // Listening
                Section {
                    Picker(L.t("Speech engine", "Bộ nhận giọng nói"), selection: $model.settings.engine) {
                        ForEach(EngineChoice.allCases) { Text(L.engineName($0)).tag($0) }
                    }
                    if model.settings.engine == .appleLive {
                        Picker(L.t("Spoken language", "Ngôn ngữ nói"), selection: $model.settings.appleLanguage) {
                            ForEach(SpokenLanguage.allCases) { Text(L.languageName($0)).tag($0) }
                        }
                        if !model.appleLiveInstalled.contains(model.settings.appleLanguage) {
                            Label(L.t("Apple's speech pack for this language is not on this iPhone, so the Auto engine will be used. (The app never downloads anything.)",
                                      "iPhone chưa có gói giọng nói của Apple cho ngôn ngữ này nên sẽ dùng bộ Tự động. (Ứng dụng không bao giờ tải gì về.)"),
                                  systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    Picker(L.t("Sound source", "Nguồn âm thanh"), selection: $model.settings.scene) {
                        ForEach(ListeningScene.allCases) { Text(L.sceneName($0)).tag($0) }
                    }
                    Picker(L.t("Microphone", "Micro"), selection: $model.settings.microphone) {
                        ForEach(MicChoice.allCases) { Text(L.micName($0)).tag($0) }
                    }
                } header: {
                    Text(L.t("Listening", "Nghe"))
                } footer: {
                    Text(L.t("Loudspeaker: for a PA system at Mass or events — uses the microphone facing the speaker, boosts quiet echoey sound and waits for whole sentences. 1-on-1: for people near the phone, reacts quickly.",
                             "Qua loa: dùng cho loa phóng thanh ở Thánh Lễ hay sự kiện — dùng micro hướng về loa, tăng âm nhỏ có tiếng vang và chờ trọn câu. Trực tiếp: cho người nói gần điện thoại, phản hồi nhanh."))
                }

                // Translator model
                Section {
                    ForEach(TranslatorModelID.allCases) { id in
                        TranslatorRow(id: id)
                    }
                    Button { showSetup = true } label: {
                        Label(L.t("AI models & setup", "Mô hình AI & cài đặt"), systemImage: "square.and.arrow.down.on.square")
                    }
                } header: {
                    Text(L.t("Translator", "Bộ dịch"))
                }

                // Display
                Section(L.t("Display", "Hiển thị")) {
                    Picker(L.t("App language", "Ngôn ngữ ứng dụng"), selection: $model.settings.appLanguage) {
                        Text("Tiếng Việt").tag(AppLanguage.vietnamese)
                        Text("English").tag(AppLanguage.english)
                    }
                    Picker(L.t("Appearance", "Giao diện"), selection: $model.settings.appearance) {
                        ForEach(Appearance.allCases) { Text(L.appearanceName($0)).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text(L.t("Text size", "Cỡ chữ"))
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $model.settings.textScale, in: 0.8...2.0, step: 0.1)
                            Image(systemName: "textformat.size.larger")
                        }
                        Text("Xin chào, rất vui được gặp bạn.")
                            .font(Theme.vietnameseFont(model.settings.mode, scale: model.settings.textScale))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Toggle(L.t("Show the original words", "Hiện lời gốc"), isOn: $model.settings.showOriginal)
                    Toggle(L.t("Keep screen on while listening", "Giữ màn hình sáng khi nghe"), isOn: $model.settings.keepScreenOn)
                }

                // Places & history
                Section {
                    Toggle(L.t("Update location when I use the app", "Cập nhật vị trí khi dùng ứng dụng"), isOn: $model.settings.rememberLocation)
                    NavigationLink(L.t("Saved places", "Địa điểm đã lưu")) { PlacesView() }
                    Button(role: .destructive) { confirmDeleteHistory = true } label: {
                        Label(L.t("Delete all history", "Xóa toàn bộ lịch sử"), systemImage: "trash")
                    }
                    .disabled(model.history.summaries.isEmpty)
                } header: {
                    Text(L.t("History & places", "Lịch sử & địa điểm"))
                } footer: {
                    Text(L.t("Location uses the iPhone's GPS only (works in Airplane Mode). It is matched to places you name and never leaves your iPhone.",
                             "Vị trí chỉ dùng GPS của iPhone (vẫn chạy ở Chế độ máy bay), được so với các địa điểm bạn đặt tên và không bao giờ rời khỏi iPhone."))
                }

                // Privacy
                Section {
                    Label(L.t("100% offline. This app contains no internet features: speech recognition and translation run on your iPhone's Neural Engine and GPU. It works in Airplane Mode.",
                              "100% ngoại tuyến. Ứng dụng không có tính năng internet: nhận giọng nói và dịch chạy trên Neural Engine và GPU của iPhone. Hoạt động cả ở Chế độ máy bay."),
                          systemImage: "lock.shield.fill")
                        .font(.footnote)
                    Label(L.t("Listen-only: the app never plays any sound.", "Chỉ nghe: ứng dụng không bao giờ phát âm thanh."),
                          systemImage: "speaker.slash.fill")
                        .font(.footnote)
                } header: {
                    Text(L.t("Privacy", "Quyền riêng tư"))
                }

                Section {
                    LabeledContent(L.t("Version", "Phiên bản"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Gemma 4 & TranslateGemma © Google (Apache 2.0 / Gemma terms) · Parakeet © NVIDIA (CC-BY-4.0) · Silero VAD (MIT) · MLX © Apple (MIT) · FluidAudio (Apache 2.0)")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle(L.t("Settings", "Cài đặt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L.t("Done", "Xong")) { dismiss() } }
            }
            .sheet(isPresented: $showSetup) { SetupView() }
            .confirmationDialog(L.t("Delete all history?", "Xóa toàn bộ lịch sử?"), isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
                Button(L.t("Delete everything", "Xóa tất cả"), role: .destructive) { model.history.deleteAll() }
            } message: {
                Text(L.t("This cannot be undone.", "Không thể hoàn tác."))
            }
        }
    }
}

private struct TranslatorRow: View {
    @Environment(AppModel.self) private var model
    let id: TranslatorModelID

    var body: some View {
        let installed = model.library.translators[id] != nil
        let fits = TranslatorModelID.supportedOnThisDevice.contains(id)
        let active = model.activeTranslator == id
        Button {
            model.settings.translator = id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(active ? Theme.accent(model.settings.mode) : Theme.secondaryText)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(id.displayName).font(.body.weight(.semibold))
                        if id == TranslatorModelID.recommendedForThisDevice {
                            Text(L.t("Best for this iPhone", "Tốt nhất cho iPhone này"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent(model.settings.mode).opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent(model.settings.mode))
                        }
                    }
                    Text(id.subtitle(model.settings.appLanguage))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text(statusText(installed: installed, fits: fits, active: active))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(installed && fits ? .green : .orange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!installed || !fits || model.sessionState != .idle)
    }

    private func statusText(installed: Bool, fits: Bool, active: Bool) -> String {
        if !fits { return L.t("Needs a 12 GB iPhone", "Cần iPhone 12 GB RAM") }
        if !installed { return L.t("Not installed (\(String(format: "%.1f", id.diskGB)) GB)", "Chưa cài (\(String(format: "%.1f", id.diskGB)) GB)") }
        if active {
            switch model.translatorState {
            case .loading: return L.t("Loading…", "Đang nạp…")
            case .ready: return L.t("In use", "Đang dùng")
            case .failed(let m): return m
            case .missing: return ""
            }
        }
        return L.t("Installed", "Đã cài")
    }
}

// MARK: - Glossary

struct GlossaryView: View {
    @Environment(AppModel.self) private var model
    @State private var source = ""
    @State private var vietnamese = ""

    var body: some View {
        List {
            Section {
                TextField(L.t("English or Spanish term", "Từ tiếng Anh hoặc Tây Ban Nha"), text: $source)
                    .textInputAutocapitalization(.never)
                TextField(L.t("Vietnamese translation", "Bản dịch tiếng Việt"), text: $vietnamese)
                Button {
                    let s = source.trimmingCharacters(in: .whitespaces)
                    let v = vietnamese.trimmingCharacters(in: .whitespaces)
                    guard !s.isEmpty, !v.isEmpty else { return }
                    model.settings.glossary.append(GlossaryEntry(source: s, vietnamese: v))
                    source = ""; vietnamese = ""
                } label: {
                    Label(L.t("Add term", "Thêm thuật ngữ"), systemImage: "plus.circle.fill")
                }
                .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty || vietnamese.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text(L.t("Names, company terms, medicines… they will always be translated your way.",
                         "Tên riêng, thuật ngữ công ty, tên thuốc… sẽ luôn được dịch theo ý bạn."))
            }

            Section {
                ForEach(model.settings.glossary) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.source).font(.body.weight(.semibold))
                        Text(entry.vietnamese).foregroundStyle(Theme.secondaryText)
                    }
                }
                .onDelete { model.settings.glossary.remove(atOffsets: $0) }
            }
        }
        .navigationTitle(L.t("My terms", "Thuật ngữ riêng"))
    }
}
