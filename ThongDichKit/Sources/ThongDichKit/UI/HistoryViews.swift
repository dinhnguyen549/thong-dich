import SwiftUI

/// All saved sessions, grouped by place or by date.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var grouping: Grouping = .place
    @State private var confirmDeleteAll = false
    @State private var pendingDelete: [UUID] = []
    @State private var namingCoordinates: (Double, Double)?
    @State private var newPlaceName = ""

    enum Grouping: String, CaseIterable, Identifiable {
        case place, date
        var id: String { rawValue }
    }

    private var history: HistoryStore { model.history }

    var body: some View {
        NavigationStack {
            Group {
                if history.summaries.isEmpty {
                    ContentUnavailableView(
                        L.t("No history yet", "Chưa có lịch sử"),
                        systemImage: "clock",
                        description: Text(L.t("Every session is saved here automatically, with date, time and place.",
                                              "Mỗi phiên được tự động lưu ở đây, kèm ngày, giờ và địa điểm.")))
                } else {
                    list
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L.t("History", "Lịch sử"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Close", "Đóng")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Label(L.t("Delete all history", "Xóa toàn bộ lịch sử"), systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .disabled(history.summaries.isEmpty)
                }
            }
            .confirmationDialog(L.t("Delete all history?", "Xóa toàn bộ lịch sử?"),
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button(L.t("Delete everything", "Xóa tất cả"), role: .destructive) { history.deleteAll() }
            } message: {
                Text(L.t("This cannot be undone.", "Không thể hoàn tác."))
            }
            .confirmationDialog(L.t("Delete these sessions?", "Xóa các phiên này?"),
                                isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
                                titleVisibility: .visible) {
                Button(L.t("Delete \(pendingDelete.count)", "Xóa \(pendingDelete.count)"), role: .destructive) {
                    history.delete(pendingDelete)
                    pendingDelete = []
                }
            }
            .alert(L.t("Name this place", "Đặt tên địa điểm"),
                   isPresented: Binding(get: { namingCoordinates != nil }, set: { if !$0 { namingCoordinates = nil } })) {
                TextField(L.t("e.g. St. Joseph Church", "VD: Nhà thờ Thánh Giuse"), text: $newPlaceName)
                Button(L.t("Save", "Lưu")) {
                    if let c = namingCoordinates, !newPlaceName.trimmingCharacters(in: .whitespaces).isEmpty {
                        history.addPlace(named: newPlaceName, latitude: c.0, longitude: c.1)
                    }
                    newPlaceName = ""
                    namingCoordinates = nil
                }
                Button(L.t("Cancel", "Hủy"), role: .cancel) { newPlaceName = "" }
            } message: {
                Text(L.t("All sessions recorded near here will be labeled with this name.",
                         "Mọi phiên ghi gần nơi này sẽ được gắn tên này."))
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Picker(L.t("Group by", "Nhóm theo"), selection: $grouping) {
                    Text(L.t("Place", "Địa điểm")).tag(Grouping.place)
                    Text(L.t("Date", "Ngày")).tag(Grouping.date)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch grouping {
            case .place: placeSections
            case .date: dateSections
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Grouped by place, then by day

    private struct PlaceGroup: Identifiable {
        var id: String
        var name: String
        var placeID: UUID?
        var coordinates: (Double, Double)?
        var sessions: [SessionSummary]
    }

    private var placeGroups: [PlaceGroup] {
        var groups: [String: PlaceGroup] = [:]
        for s in history.summaries {
            let key: String
            let name: String
            if let pid = s.placeID, let pname = s.placeName {
                key = pid.uuidString; name = pname
            } else if s.hasCoordinates {
                key = "unnamed"; name = L.t("Unnamed places", "Nơi chưa đặt tên")
            } else {
                key = "none"; name = L.t("No location", "Không có vị trí")
            }
            var g = groups[key] ?? PlaceGroup(id: key, name: name, placeID: s.placeID, coordinates: nil, sessions: [])
            g.sessions.append(s)
            if g.coordinates == nil, let lat = s.latitude, let lon = s.longitude { g.coordinates = (lat, lon) }
            groups[key] = g
        }
        return groups.values.sorted {
            ($0.sessions.first?.startedAt ?? .distantPast) > ($1.sessions.first?.startedAt ?? .distantPast)
        }
    }

    @ViewBuilder private var placeSections: some View {
        ForEach(placeGroups) { group in
            Section {
                let days = Dictionary(grouping: group.sessions) { Calendar.current.startOfDay(for: $0.startedAt) }
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Text(L.dayTitle(day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(.uppercase)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
                    ForEach(days[day] ?? []) { s in
                        row(s, showPlace: false)
                    }
                }
            } header: {
                HStack {
                    Label(group.name, systemImage: group.placeID != nil ? "mappin.circle.fill" : "mappin.slash")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Spacer()
                    Menu {
                        if group.id == "unnamed", let c = group.coordinates {
                            Button { namingCoordinates = c } label: {
                                Label(L.t("Name this place", "Đặt tên địa điểm"), systemImage: "mappin.and.ellipse")
                            }
                        }
                        Button(role: .destructive) { pendingDelete = group.sessions.map(\.id) } label: {
                            Label(L.t("Delete all here", "Xóa tất cả ở đây"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.body)
                    }
                }
            }
        }
    }

    // MARK: Grouped by day

    @ViewBuilder private var dateSections: some View {
        let days = Dictionary(grouping: history.summaries) { Calendar.current.startOfDay(for: $0.startedAt) }
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
            Section {
                ForEach(days[day] ?? []) { s in row(s, showPlace: true) }
            } header: {
                HStack {
                    Text(L.dayTitle(day)).font(.headline).foregroundStyle(.primary).textCase(nil)
                    Spacer()
                    Button(role: .destructive) { pendingDelete = (days[day] ?? []).map(\.id) } label: {
                        Image(systemName: "trash").font(.footnote)
                    }
                    .accessibilityLabel(L.t("Delete this day", "Xóa ngày này"))
                }
            }
        }
    }

    // MARK: Row

    private func row(_ s: SessionSummary, showPlace: Bool) -> some View {
        NavigationLink {
            SessionDetailView(summaryID: s.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent(s.mode).opacity(0.15)).frame(width: 38, height: 38)
                    Image(systemName: s.source == .recording ? "waveform" : L.modeIcon(s.mode))
                        .foregroundStyle(Theme.accent(s.mode))
                        .font(.subheadline.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(L.time(s.startedAt)) – \(L.time(s.endedAt))")
                            .font(.subheadline.weight(.semibold))
                        Text("· \(L.modeName(s.mode))").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    if showPlace, let place = s.placeName {
                        Label(place, systemImage: "mappin").font(.caption).foregroundStyle(.pink)
                    }
                    if let file = s.fileName {
                        Text(file).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                    Text(s.preview)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions {
            Button(role: .destructive) { history.delete([s.id]) } label: {
                Label(L.t("Delete", "Xóa"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let summaryID: UUID
    @State private var record: SessionRecord?
    @State private var confirmDelete = false
    @State private var newPlace = false
    @State private var placeName = ""

    private var history: HistoryStore { model.history }

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(record)
                        ForEach(record.lines) { line in
                            LineCard(line: line, mode: record.mode, scale: model.settings.textScale,
                                     showOriginal: true,
                                     timeText: record.source == .recording
                                        ? HistoryStore.formatOffset(line.offset) : L.time(line.date))
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(record.map { L.dayTitle($0.startedAt) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let record {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: HistoryStore.exportText(record, language: model.settings.appLanguage)) {
                            Label(L.t("Share text", "Chia sẻ văn bản"), systemImage: "square.and.arrow.up")
                        }
                        Menu {
                            ForEach(history.places) { place in
                                Button(place.name) { assign(place) }
                            }
                            Button { newPlace = true } label: {
                                Label(L.t("New place…", "Địa điểm mới…"), systemImage: "plus")
                            }
                            if record.placeID != nil {
                                Button(role: .destructive) { assign(nil) } label: {
                                    Label(L.t("Remove place", "Bỏ địa điểm"), systemImage: "mappin.slash")
                                }
                            }
                        } label: {
                            Label(L.t("Change place", "Đổi địa điểm"), systemImage: "mappin.and.ellipse")
                        }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(L.t("Delete", "Xóa"), systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog(L.t("Delete this session?", "Xóa phiên này?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L.t("Delete", "Xóa"), role: .destructive) {
                history.delete([summaryID])
                dismiss()
            }
        }
        .alert(L.t("New place", "Địa điểm mới"), isPresented: $newPlace) {
            TextField(L.t("Place name", "Tên địa điểm"), text: $placeName)
            Button(L.t("Save", "Lưu")) {
                let name = placeName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let r = record else { return }
                let place: SavedPlace
                if let lat = r.latitude, let lon = r.longitude {
                    place = history.addPlace(named: name, latitude: lat, longitude: lon)
                } else {
                    place = history.addManualPlace(named: name)
                }
                assign(place)
                placeName = ""
            }
            Button(L.t("Cancel", "Hủy"), role: .cancel) { placeName = "" }
        }
        .task { record = history.record(summaryID) }
    }

    private func header(_ r: SessionRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Chip(icon: L.modeIcon(r.mode), text: L.modeName(r.mode), tint: Theme.accent(r.mode))
                    if r.source == .recording { Chip(icon: "waveform", text: L.t("Recording", "Bản ghi")) }
                }
                Label("\(L.dateTime(r.startedAt)) – \(L.time(r.endedAt))", systemImage: "calendar")
                    .font(.subheadline)
                Label(r.placeName ?? L.t("No place", "Chưa có địa điểm"), systemImage: "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(r.placeName == nil ? Theme.secondaryText : .pink)
                if let f = r.fileName {
                    Label(f, systemImage: "doc").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func assign(_ place: SavedPlace?) {
        history.assign([summaryID], to: place)
        record = history.record(summaryID)
    }
}

// MARK: - Place for the current session (from the Home screen)

struct PlacePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(L.t("Name this place (e.g. St. Joseph Church)", "Đặt tên nơi này (VD: Nhà thờ Thánh Giuse)"), text: $newName)
                        Button(L.t("Save", "Lưu")) {
                            model.nameCurrentPlace(newName)
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text(model.currentHasCoordinates
                         ? L.t("Next time you use the app here, this place is chosen automatically (GPS, on your iPhone only).",
                               "Lần sau dùng ứng dụng ở đây, địa điểm này sẽ tự được chọn (GPS, chỉ trên iPhone).")
                         : L.t("No GPS position yet — the name is saved for this session only.",
                               "Chưa có vị trí GPS — tên chỉ lưu cho phiên này."))
                }

                if !model.history.places.isEmpty {
                    Section(L.t("Saved places", "Địa điểm đã lưu")) {
                        ForEach(model.history.places) { place in
                            Button {
                                model.chooseCurrentPlace(place)
                                dismiss()
                            } label: {
                                HStack {
                                    Label(place.name, systemImage: "mappin.circle.fill")
                                    Spacer()
                                    if model.currentRecord?.placeID == place.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent(model.settings.mode))
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                    Button {
                        model.refreshCurrentLocation()
                        dismiss()
                    } label: {
                        Label(L.t("Update location now", "Cập nhật vị trí ngay"), systemImage: "location.fill")
                    }
                }
            }
            .navigationTitle(L.t("Place", "Địa điểm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("Close", "Đóng")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Manage places (from Settings)

struct PlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: SavedPlace?
    @State private var name = ""

    var body: some View {
        List {
            if model.history.places.isEmpty {
                Text(L.t("No places yet. Name a place from the Home screen or History.",
                         "Chưa có địa điểm. Hãy đặt tên từ màn hình chính hoặc Lịch sử."))
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.history.places) { place in
                Button {
                    name = place.name
                    renaming = place
                } label: {
                    HStack {
                        Label(place.name, systemImage: "mappin.circle.fill").foregroundStyle(.primary)
                        Spacer()
                        let count = model.history.summaries.filter { $0.placeID == place.id }.count
                        Text("\(count)").foregroundStyle(Theme.secondaryText)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { model.history.deletePlace(place.id) } label: {
                        Label(L.t("Delete", "Xóa"), systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(L.t("Places", "Địa điểm"))
        .alert(L.t("Rename place", "Đổi tên địa điểm"),
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L.t("Name", "Tên"), text: $name)
            Button(L.t("Save", "Lưu")) {
                if let p = renaming, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.history.renamePlace(p.id, to: name)
                }
                renaming = nil
            }
            Button(L.t("Cancel", "Hủy"), role: .cancel) { renaming = nil }
        }
    }
}
