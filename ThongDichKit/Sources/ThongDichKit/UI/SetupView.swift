import SwiftUI
import UniformTypeIdentifiers

/// Shows which AI models are on the iPhone and how to add them — without any internet access.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow(
                        title: L.t("Speech recognition", "Nhận giọng nói"),
                        detail: "Parakeet Ultra · 0.6 GB",
                        ok: model.library.parakeetDirectory != nil,
                        state: model.speechState)
                    statusRow(
                        title: L.t("Voice detector", "Bộ phát hiện giọng nói"),
                        detail: "Silero VAD · 1 MB",
                        ok: model.library.vadModelURL != nil,
                        state: nil)
                    ForEach(TranslatorModelID.allCases) { id in
                        let fits = TranslatorModelID.supportedOnThisDevice.contains(id)
                        statusRow(
                            title: id.displayName,
                            detail: String(format: "%.1f GB", id.diskGB) + (fits ? "" : " · " + L.t("needs 12 GB iPhone", "cần iPhone 12 GB")),
                            ok: model.library.translators[id] != nil,
                            state: model.activeTranslator == id ? model.translatorState : nil,
                            optional: id != .gemma4E2B && id != .translateGemma4B)
                    }
                } header: {
                    Text(L.t("On this iPhone", "Trên iPhone này"))
                } footer: {
                    Text(L.t("Required: speech recognition, voice detector and at least one translator. TranslateGemma is optional; Gemma 4 E4B is optional and only for 12 GB iPhones (iPhone Air).",
                             "Bắt buộc: nhận giọng nói, bộ phát hiện giọng nói và ít nhất một bộ dịch. TranslateGemma là tùy chọn; Gemma 4 E4B tùy chọn, chỉ cho iPhone 12 GB (iPhone Air)."))
                }

                if let progress = model.importProgress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.t("Installing models… keep the app open", "Đang cài mô hình… hãy giữ ứng dụng mở")).font(.subheadline.weight(.semibold))
                            ProgressView(value: progress)
                        }
                    }
                }

                Section {
                    step(1, L.t("On your Windows PC, run Get-Models.bat (from the app package). It downloads the models and makes a few .tdpack files in the ThongDich-Transfer folder.",
                                "Trên máy tính Windows, chạy Get-Models.bat (trong gói ứng dụng). Tệp này tải mô hình và tạo vài tệp .tdpack trong thư mục ThongDich-Transfer."))
                    step(2, L.t("Connect the iPhone with a cable and open the Apple Devices app (or iTunes) › your iPhone › Files › Thông Dịch.",
                                "Cắm iPhone vào máy tính, mở ứng dụng Apple Devices (hoặc iTunes) › iPhone › Tệp › Thông Dịch."))
                    step(3, L.t("Drag all the .tdpack files in. When copying finishes, open this screen — the app installs them by itself (no internet).",
                                "Kéo tất cả tệp .tdpack vào. Khi chép xong, mở màn hình này — ứng dụng tự cài đặt (không cần internet)."))
                } header: {
                    Text(L.t("Add the models from your PC", "Thêm mô hình từ máy tính"))
                }

                Section {
                    Button { picking = true } label: {
                        Label(L.t("Import from Files (USB drive…)", "Nhập từ Tệp (USB…)"), systemImage: "folder.badge.plus")
                    }
                    .disabled(model.importProgress != nil)
                    Button {
                        Task { await model.reloadAll() }
                    } label: {
                        Label(L.t("Check again / install copied packs", "Kiểm tra lại / cài gói đã chép"), systemImage: "arrow.clockwise")
                    }
                } footer: {
                    Text(L.t("Another way: put the .tdpack files (or the ThongDichModels folder) on a USB-C flash drive formatted exFAT, plug it into the iPhone and pick them here. Everything is copied on the phone; nothing is downloaded.",
                             "Cách khác: chép các tệp .tdpack (hoặc thư mục ThongDichModels) vào USB-C định dạng exFAT, cắm vào iPhone rồi chọn ở đây. Mọi thứ được chép trên điện thoại; không tải gì từ mạng."))
                }

                Section {
                    LabeledContent(L.t("Free space on iPhone", "Dung lượng trống"), value: freeSpace)
                    LabeledContent(L.t("Memory (RAM)", "Bộ nhớ (RAM)"),
                                   value: String(format: "%.0f GB", Double(TranslatorModelID.deviceRAM) / 1_000_000_000))
                }
            }
            .navigationTitle(L.t("AI models", "Mô hình AI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L.t("Done", "Xong")) { dismiss() } }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder, .data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.importPicked(urls) }
            }
            .task { await model.reloadAll() }
        }
    }

    private func statusRow(title: String, detail: String, ok: Bool, state: AppModel.LoadState?, optional: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : (optional ? "circle.dashed" : "exclamationmark.circle.fill"))
                .font(.title3)
                .foregroundStyle(ok ? .green : (optional ? Theme.secondaryText : .orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                if let state {
                    switch state {
                    case .loading: Text(L.t("Loading…", "Đang nạp…")).font(.caption).foregroundStyle(.orange)
                    case .ready: Text(L.t("Ready", "Sẵn sàng")).font(.caption).foregroundStyle(.green)
                    case .failed(let m): Text(m).font(.caption).foregroundStyle(.red)
                    case .missing: EmptyView()
                    }
                }
            }
            Spacer()
            Text(ok ? L.t("Installed", "Đã cài") : (optional ? L.t("Optional", "Tùy chọn") : L.t("Missing", "Thiếu")))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ok ? .green : Theme.secondaryText)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .frame(width: 26, height: 26)
                .background(Theme.accent(model.settings.mode).opacity(0.15), in: Circle())
                .foregroundStyle(Theme.accent(model.settings.mode))
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private var freeSpace: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let bytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
