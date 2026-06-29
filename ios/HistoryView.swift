import SwiftUI
import MapKit

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var shareItems:         [Any] = []
    @State private var showShare           = false
    @State private var showExportPicker    = false
    @State private var pendingSession:     TrackSession?
    @State private var previewSession:     TrackSession?
    @State private var showPreview         = false

    var body: some View {
        NavigationStack {
            Group {
                if state.sessions.isEmpty {
                    ContentUnavailableView(
                        "保存された軌跡はありません",
                        systemImage: "map",
                        description: Text("追跡を開始して「停止・保存」を押すと、ここに表示されます。")
                    )
                } else {
                    List {
                        ForEach(state.sessions) { session in
                            SessionRow(session: session) {
                                previewSession = session
                                showPreview = true
                            } onExport: {
                                pendingSession = session
                                showExportPicker = true
                            } onDelete: {
                                state.deleteSession(session)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("軌跡履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: shareItems)
        }
        .sheet(isPresented: $showPreview) {
            if let s = previewSession { TrackPreviewView(session: s) }
        }
        .confirmationDialog("エクスポート形式を選択", isPresented: $showExportPicker) {
            Button("GPX（Google Maps・Strava 対応）") { doExport(format: "gpx") }
            Button("CSV（Excel・スプレッドシート用）")  { doExport(format: "csv") }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func doExport(format: String) {
        guard let session = pendingSession else { return }
        do {
            let url = format == "gpx"
                ? try GPXExporter.tempURL(for: session)
                : try CSVExporter.tempURL(for: session)
            shareItems = [url]
            showShare  = true
        } catch {
            // Surface error via state
            state.locationError = "エクスポートに失敗しました: \(error.localizedDescription)"
        }
    }
}

// ── Session row ────────────────────────────────────────────────────────────

struct SessionRow: View {
    let session:  TrackSession
    let onPreview: () -> Void
    let onExport:  () -> Void
    let onDelete:  () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title + duration
            HStack {
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(session.formattedDuration)
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Stats
            HStack(spacing: 16) {
                Label(session.formattedDistance,      systemImage: "arrow.left.and.right")
                Label("\(session.points.count) pt",   systemImage: "mappin")
            }
            .font(.caption).foregroundStyle(.secondary)
            // Actions
            HStack(spacing: 8) {
                Button(action: onPreview) {
                    Label("地図", systemImage: "map")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered).tint(.cyan)

                Button(action: onExport) {
                    Label("書き出す", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered).tint(.secondary)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

// ── Track preview ──────────────────────────────────────────────────────────

struct TrackPreviewView: View {
    let session: TrackSession
    @Environment(\.dismiss) private var dismiss

    var coordinates: [CLLocationCoordinate2D] {
        session.points.map(\.coordinate)
    }

    var body: some View {
        NavigationStack {
            Map {
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.cyan, lineWidth: 3)
                }
                // Start marker (green)
                if let first = coordinates.first {
                    Annotation("スタート", coordinate: first) {
                        Circle().fill(.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                // End marker (gray)
                if let last = coordinates.last, coordinates.count > 1 {
                    Annotation("ゴール", coordinate: last) {
                        Circle().fill(.gray)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard)
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 24) {
                        Label(session.formattedDistance, systemImage: "arrow.left.and.right")
                        Label(session.formattedDuration,  systemImage: "clock")
                        Label("\(session.points.count) pt", systemImage: "mappin")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
