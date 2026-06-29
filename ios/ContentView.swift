import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
                  distance: 1000)
    )
    @State private var isFollowing   = true
    @State private var showHistory   = false
    @State private var shareItems:   [Any] = []
    @State private var showShare     = false
    @State private var showExportPicker = false
    @State private var pendingExportSession: TrackSession?

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            VStack(spacing: 0) {
                banners
                infoPanel
                controlBar
            }
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .top)
        // Auto-follow during tracking
        .onChange(of: state.currentLocation) { _, loc in
            guard let loc, isFollowing else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: loc.coordinate, distance: 400))
            }
        }
        .alert("エラー", isPresented: Binding(
            get: { state.locationError != nil },
            set: { if !$0 { state.locationError = nil } }
        )) {
            Button("OK") { state.locationError = nil }
        } message: {
            Text(state.locationError ?? "")
        }
        .sheet(isPresented: $showHistory) {
            HistoryView().environmentObject(state)
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: shareItems)
        }
        .confirmationDialog("エクスポート形式を選択", isPresented: $showExportPicker) {
            Button("GPX（Google Maps・Strava 対応）") { doExport(format: "gpx") }
            Button("CSV（Excel・スプレッドシート用）")  { doExport(format: "csv") }
            Button("キャンセル", role: .cancel) {}
        }
        .onAppear {
            if state.authStatus == .notDetermined { state.requestPermission() }
        }
    }

    // ── Map ────────────────────────────────────────────────────────────────

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            if state.coordinates.count >= 2 {
                MapPolyline(coordinates: state.coordinates)
                    .stroke(.cyan, lineWidth: 3)
            }
            if let loc = state.currentLocation {
                MapCircle(center: loc.coordinate, radius: max(loc.horizontalAccuracy, 8))
                    .foregroundStyle(.cyan.opacity(0.08))
                    .stroke(.cyan.opacity(0.5), lineWidth: 1.5)
                Annotation("", coordinate: loc.coordinate) {
                    LocationDot(isTracking: state.isTracking)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange { _ in
            // Stop auto-follow when the user manually pans
            isFollowing = false
        }
        .ignoresSafeArea()
    }

    // ── Banners ────────────────────────────────────────────────────────────

    @ViewBuilder
    private var banners: some View {
        // No permission
        if state.authStatus == .denied || state.authStatus == .restricted {
            Banner(icon: "location.slash.fill", color: .red,
                   text: "位置情報のアクセスが許可されていません。") {
                Button("設定を開く", action: state.openSettings)
                    .buttonStyle(.bordered).tint(.red)
            }
        }
        // Full accuracy → GPS might be active → warn
        if #available(iOS 14.0, *),
           state.accuracyAuth == .fullAccuracy,
           state.currentLocation != nil {
            Banner(icon: "antenna.radiowaves.left.and.right", color: .yellow,
                   text: "「正確な位置情報」がオンです。設定 → 位置情報 でオフにするとGPS無しになります。") {
                Button("設定", action: state.openSettings)
                    .buttonStyle(.bordered).tint(.yellow)
            }
        }
    }

    // ── Info panel ─────────────────────────────────────────────────────────

    private var infoPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                InfoCard(label: "測位精度") {
                    let acc = state.currentLocation.map { Int($0.horizontalAccuracy) }
                    NumericValue(value: acc.map(String.init) ?? "--", unit: "m")
                }
                InfoCard(label: "測位方式", flex: 2) {
                    Text(state.positioningMethod.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.positioningMethod.tintColor)
                        .lineLimit(2).minimumScaleFactor(0.75)
                }
                InfoCard(label: "速度") {
                    NumericValue(
                        value: state.speedKmh.map { String(format: "%.1f", $0) } ?? "--",
                        unit: "km/h")
                }
            }
            HStack(spacing: 6) {
                InfoCard(label: "緯度 / 経度", flex: 2) {
                    Text(state.currentLocation.map {
                        String(format: "%.6f,  %.6f",
                               $0.coordinate.latitude, $0.coordinate.longitude)
                    } ?? "-- / --")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan).lineLimit(1).minimumScaleFactor(0.7)
                }
                InfoCard(label: "移動距離") {
                    let d = state.totalDistance
                    NumericValue(
                        value: d >= 1000
                            ? String(format: "%.2f", d / 1000)
                            : String(format: "%.0f", d),
                        unit: d >= 1000 ? "km" : "m")
                }
                InfoCard(label: "ポイント") {
                    NumericValue(value: "\(state.coordinates.count)", unit: "pt")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // ── Control bar ────────────────────────────────────────────────────────

    private var controlBar: some View {
        HStack(spacing: 8) {
            // Start / Stop (primary)
            Button {
                if state.isTracking { state.stopTracking() }
                else                { state.startTracking(); isFollowing = true }
            } label: {
                Label(
                    state.isTracking ? "停止・保存" : "追跡開始",
                    systemImage: state.isTracking ? "stop.fill" : "location.fill"
                )
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .tint(state.isTracking ? .red : .cyan)
            .controlSize(.large)

            // Center
            IconButton(systemImage: "location.circle") {
                isFollowing = true
                if let loc = state.currentLocation {
                    withAnimation {
                        cameraPosition = .camera(MapCamera(
                            centerCoordinate: loc.coordinate, distance: 400))
                    }
                }
            }
            .disabled(state.currentLocation == nil)

            // Clear
            IconButton(systemImage: "trash") { state.clearTrack() }
                .disabled(state.coordinates.isEmpty)

            Spacer()

            // Export
            IconButton(systemImage: "square.and.arrow.up") {
                pendingExportSession = state.activeSession ?? state.sessions.first
                if pendingExportSession != nil { showExportPicker = true }
            }
            .disabled(state.coordinates.isEmpty && state.sessions.isEmpty)

            // History with badge
            ZStack(alignment: .topTrailing) {
                IconButton(systemImage: "clock.arrow.circlepath") { showHistory = true }
                if !state.sessions.isEmpty {
                    Text("\(state.sessions.count)")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.cyan).foregroundStyle(.black)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
    }

    // ── Export ─────────────────────────────────────────────────────────────

    private func doExport(format: String) {
        guard let session = pendingExportSession else { return }
        do {
            let url = format == "gpx"
                ? try GPXExporter.tempURL(for: session)
                : try CSVExporter.tempURL(for: session)
            shareItems = [url]
            showShare  = true
        } catch {
            state.locationError = "エクスポートに失敗しました: \(error.localizedDescription)"
        }
    }
}

// ── Reusable sub-views ─────────────────────────────────────────────────────

struct LocationDot: View {
    let isTracking: Bool
    var body: some View {
        Circle()
            .fill(.cyan)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .cyan.opacity(0.6), radius: isTracking ? 6 : 2)
            .scaleEffect(isTracking ? 1.0 : 0.85)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true),
                       value: isTracking)
    }
}

struct Banner<Trailing: View>: View {
    let icon:     String
    let color:    Color
    let text:     String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
    }
}

struct InfoCard<Content: View>: View {
    let label:  String
    var flex:   CGFloat = 1
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            content()
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity * flex)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct NumericValue: View {
    let value: String
    let unit:  String
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct IconButton: View {
    let systemImage: String
    let action:      () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.large)
    }
}

// ── UIActivityViewController wrapper ──────────────────────────────────────

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
