import SwiftUI
import UniformTypeIdentifiers

/// Translate a recorded conversation, homily or meeting (audio or video file).
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var pickedURL: URL?
    @State private var loudspeaker = false

    private static let types: [UTType] = [.audio, .movie, .mpeg4Audio, .mp3, .wav, .aiff, .mpeg4Movie, .quickTimeMovie]

    var body: some View {
        NavigationStack {
            Group {
                if let job = model.fileJob {
                    JobProgressView(job: job)
                } else {
                    chooser
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L.t("Translate a recording", "Dịch bản ghi âm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.fileJob?.isRunning == true ? L.t("Hide", "Ẩn") : L.t("Close", "Đóng")) {
                        if model.fileJob?.isRunning == false { model.dismissFileJob() }
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { result in
                if case .success(let url) = result { pickedURL = url }
            }
            .onAppear {
                loudspeaker = model.settings.mode == .mass
                if let opened = model.openedRecording {
                    pickedURL = opened
                    model.openedRecording = nil
                }
            }
        }
    }

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button { picking = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: pickedURL == nil ? "waveform.badge.plus" : "waveform")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Theme.gradient(model.settings.mode))
                        Text(pickedURL?.lastPathComponent ?? L.t("Choose a recording", "Chọn bản ghi"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(L.t("Voice Memos, Files, or a video. Audio is never played.",
                                 "Ghi âm, Tệp hoặc video. Âm thanh không được phát ra."))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Theme.accent(model.settings.mode).opacity(0.45),
                                          style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ModePicker()

                Card {
                    Toggle(isOn: $loudspeaker) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.t("Recorded through a loudspeaker", "Thu qua loa phóng thanh"))
                                .font(.body.weight(.semibold))
                            Text(L.t("Church, hall or event — extra clean-up for echo.",
                                     "Nhà thờ, hội trường, sự kiện — lọc thêm tiếng vang."))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                Button {
                    guard let url = pickedURL else { return }
                    model.translateRecording(url, loudspeaker: loudspeaker)
                } label: {
                    Label(L.t("Transcribe & translate", "Chép lời & dịch"), systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.gradient(model.settings.mode), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(pickedURL == nil || model.needsSetup)
                .opacity(pickedURL == nil || model.needsSetup ? 0.5 : 1)

                if model.needsSetup {
                    Text(L.t("Add the AI models first (Settings › AI models).", "Hãy thêm mô hình AI trước (Cài đặt › Mô hình AI)."))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text(L.t("Keep the app open while it works — the screen stays on.",
                         "Giữ ứng dụng mở trong khi xử lý — màn hình sẽ luôn sáng."))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

private struct JobProgressView: View {
    @Environment(AppModel.self) private var model
    let job: FileJob

    var body: some View {
        VStack(spacing: 0) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "waveform")
                        Text(job.displayName).font(.headline).lineLimit(1)
                        Spacer()
                        if job.durationSeconds > 0 {
                            Text(HistoryStore.formatOffset(job.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    ProgressView(value: job.phase == .done ? 1 : job.overallProgress)
                        .tint(Theme.accent(model.settings.mode))
                    HStack {
                        Text(phaseText).font(.footnote).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if job.phase == .done, let text = exportText {
                            ShareLink(item: text) {
                                Label(L.t("Share", "Chia sẻ"), systemImage: "square.and.arrow.up")
                                    .font(.footnote.weight(.semibold))
                            }
                        } else if job.isRunning {
                            Button(L.t("Cancel", "Hủy"), role: .destructive) { model.dismissFileJob() }
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            .padding()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(job.pipeline.lines) { line in
                        LineCard(line: line, mode: model.settings.mode, scale: model.settings.textScale,
                                 showOriginal: model.settings.showOriginal,
                                 timeText: HistoryStore.formatOffset(line.offset))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }

    private var phaseText: String {
        switch job.phase {
        case .preparing: return L.t("Opening file…", "Đang mở tệp…")
        case .working:
            return L.t("Listening and translating… \(Int(job.overallProgress * 100))%",
                       "Đang nghe và dịch… \(Int(job.overallProgress * 100))%")
        case .finishing: return L.t("Finishing the last sentences…", "Đang dịch những câu cuối…")
        case .done: return L.t("Done · saved to History", "Xong · đã lưu vào Lịch sử")
        case .failed(let message): return message
        case .cancelled: return L.t("Cancelled", "Đã hủy")
        }
    }

    private var exportText: String? {
        let record = SessionRecord(
            source: .recording, fileName: job.displayName, mode: model.settings.mode,
            startedAt: Date(), endedAt: Date(), lines: job.pipeline.lines)
        return HistoryStore.exportText(record, language: model.settings.appLanguage)
    }
}
