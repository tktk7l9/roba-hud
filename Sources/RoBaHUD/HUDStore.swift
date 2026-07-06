import AppKit
import Foundation
import Observation

/// Central app state: keymap + geometry, HID monitoring, layer inference,
/// live highlights.
@MainActor
@Observable
final class HUDStore {
    var keymap: Keymap?
    var geometry: [KeyGeometry] = []
    var layoutBounds = LayoutBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)
    var loadError: String?

    /// The layer currently rendered.
    var displayedLayer = 0
    /// Manual pin: while set, inference must not change displayedLayer.
    var pinnedLayer: Int? {
        didSet { engine?.pinned = pinnedLayer }
    }

    /// Positions (0-based binding indices) currently lit, on the displayed layer.
    var highlighted: Set<Int> = []

    enum HIDState {
        case off                // not started (no keymap yet)
        case running            // monitor up, waiting for / receiving events
        case permissionNeeded   // TCC denied or open failed
    }
    var hidState: HIDState = .off
    var deviceConnected = false
    /// Whether this Mac is (believed to be) the currently active BT profile.
    /// roBa keeps its BLE link to every bonded host alive even while a
    /// different profile is active, so connect/disconnect can't tell us
    /// this — only the live HID stream can. True the moment any report
    /// arrives (including the bt_sel_mN marker, which fires the instant a
    /// switch lands on us); false after `activityTimeout` of silence.
    var isActiveProfile = true
    private var lastHIDActivity = Date()
    private let activityTimeout: TimeInterval = 45

    var opacity: Double = Prefs.opacity {
        didSet { Prefs.opacity = opacity }
    }

    let statsStore = StatsStore()
    let insightsStore = InsightsStore()
    let battery = BatteryCenter()
    var showHeatmap = false
    var showStatsSheet = false
    var showDeviceSheet = false

    /// BT profile this Mac is bonded on — auto-learned from the firmware
    /// profile marker, or set manually in the device sheet.
    var thisMacProfile: Int? = Prefs.thisMacProfile {
        didSet { Prefs.thisMacProfile = thisMacProfile }
    }
    /// User labels per BT profile.
    var btLabels: [Int: String] = Prefs.btLabels {
        didSet { Prefs.btLabels = btLabels }
    }

    /// Compact bar mode: current layer + recent keys only.
    var compactMode: Bool = Prefs.compactMode {
        didSet { Prefs.compactMode = compactMode }
    }
    /// Mouse events pass through the panel (disabled while editing).
    var clickThrough: Bool = Prefs.clickThrough {
        didSet { Prefs.clickThrough = clickThrough }
    }

    struct RecentPress: Identifiable, Equatable {
        let id: UUID
        let text: String
        let at: Date
    }
    /// Last few key presses for the compact bar (newest first).
    var recentPresses: [RecentPress] = []

    /// Click-through would make the gear menu unreachable; require the menu
    /// bar item as an escape hatch.
    func setClickThrough(_ on: Bool) {
        if on, !battery.menuBarEnabled {
            statusToast = "クリック透過はメニューバー表示が有効なときのみ使えます（解除手段の確保のため）"
            return
        }
        clickThrough = on
        if on {
            statusToast = "クリック透過ON — 解除はメニューバーのバッテリーメニューから"
        }
    }

    // MARK: - Edit mode / git state

    var editMode = false {
        didSet { if !editMode { editingPosition = nil } }
    }
    /// Position whose BindingPicker popover is open.
    var editingPosition: Int?
    /// Uncommitted keymap diff (nil = clean).
    var gitDiff: String?
    var showDiffDetail = false
    var editError: String?
    /// Human summaries of edits since the last commit (→ commit message).
    var editSummaries: [String] = []

    enum PipelineState: Equatable {
        case idle
        case running(String)
        case succeeded(String)
        case failed(String)

        var isRunning: Bool { if case .running = self { true } else { false } }
    }
    var pipelineState: PipelineState = .idle
    var pipelineLog: [String] = []
    var downloadedFirmwareURL: URL?
    var showFlashGuide = false
    var statusToast: String?

    private var engine: InferenceEngine?
    private var monitor: HIDMonitor?
    private var tickTimer: Timer?
    private var activityTimer: Timer?
    private var fileWatcher: FileWatcher?

    private var pipeline: GitPipeline { GitPipeline(repoPath: Prefs.zmkConfigPath) }

    init() {}

    // MARK: - Loading

    func loadAll() {
        loadGeometry()
        loadKeymap()
    }

    func loadGeometry() {
        do {
            let data = try Data(contentsOf: Prefs.layoutJSONURL)
            let keys = try GeometryLoader.load(json: data)
            geometry = keys
            layoutBounds = GeometryLoader.bounds(of: keys)
        } catch {
            loadError = "レイアウト読込失敗 (\(Prefs.layoutJSONURL.path)): \(error)"
        }
    }

    /// (Re)load the keymap. On failure the last good keymap stays rendered and
    /// the error is surfaced in a banner.
    func loadKeymap() {
        do {
            let url = Prefs.keymapURL
            let source = try String(contentsOf: url, encoding: .utf8)
            let parsed = try KeymapParser.parse(source: source, fileURL: url)
            if !geometry.isEmpty,
               let count = parsed.layers.first?.bindings.count, count != geometry.count {
                throw ParseError(message: "bindings数(\(count))がレイアウトのキー数(\(geometry.count))と一致しません")
            }
            keymap = parsed
            loadError = nil
            if displayedLayer >= parsed.layers.count { displayedLayer = 0 }
            if engine == nil {
                var fresh = InferenceEngine(keymap: parsed)
                fresh.pinned = pinnedLayer
                engine = fresh
            } else {
                engine?.reload(keymap: parsed)
            }
        } catch {
            loadError = "keymap 読込失敗: \(error)"
        }
    }

    // MARK: - Layer selection

    func selectLayer(_ index: Int) {
        guard let keymap, keymap.layers.indices.contains(index) else { return }
        displayedLayer = index
        if pinnedLayer != nil { pinnedLayer = index }
    }

    func togglePin() {
        pinnedLayer = pinnedLayer == nil ? displayedLayer : nil
    }

    // MARK: - HID monitoring

    func startMonitoring() {
        guard monitor == nil, engine != nil else { return }
        if HIDMonitor.Access.current() != .granted {
            HIDMonitor.requestAccess()   // shows the system prompt once
        }
        let m = HIDMonitor()
        m.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleHID(event) }
        }
        m.onOpenFailure = { [weak self] _ in
            Task { @MainActor in self?.hidState = .permissionNeeded }
        }
        m.start()
        monitor = m
        hidState = HIDMonitor.Access.current() == .granted ? .running : .permissionNeeded
        activityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkActivityTimeout() }
        }
    }

    private func checkActivityTimeout() {
        guard isActiveProfile, Date().timeIntervalSince(lastHIDActivity) > activityTimeout else { return }
        isActiveProfile = false
    }

    /// After granting the permission in System Settings the TCC grant only
    /// applies to a fresh process: relaunch (packaged app) or plain restart.
    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]
            try? process.run()
        }
        NSApp.terminate(nil)
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    private func handleHID(_ event: HIDEvent) {
        if case .connection(let up) = event {
            deviceConnected = up
            if !up { isActiveProfile = false }
        } else {
            lastHIDActivity = Date()
            isActiveProfile = true
        }
        // Profile markers are ours alone — consume them before inference so
        // they never show up as highlights, stats or insights.
        if case .key(let page, let usage, let down) = event,
           let marker = ProfileMarker.decode(page: page, usage: usage) {
            if down { handleProfileMarker(marker) }
            return
        }
        guard var engine else { return }
        engine.handle(event, at: Date())
        if let press = engine.lastPress {
            statsStore.record(layer: press.layer, position: press.position)
            recordRecentPress(press)
            if let key = engine.lastKeyEvent {
                insightsStore.record(layer: press.layer, page: key.page, usage: key.usage, mods: key.mods)
                engine.lastKeyEvent = nil
            }
            engine.lastPress = nil
        }
        applyEngine(engine)
    }

    private func handleProfileMarker(_ marker: ProfileMarker) {
        switch marker {
        case .selected(let n):
            thisMacProfile = n
            let label = btLabels[n].map { "（\($0)）" } ?? ""
            statusToast = "BT\(n) に切替\(label) — このMacのプロファイルとして記録"
        case .cleared:
            if let n = thisMacProfile {
                statusToast = "BT\(n) のボンドをクリアしました"
            } else {
                statusToast = "現在プロファイルのボンドをクリアしました"
            }
            thisMacProfile = nil
        }
    }

    private func recordRecentPress(_ press: (layer: Int, position: Int)) {
        guard let keymap else { return }
        let binding = keymap.effective(layer: press.layer, position: press.position)
        let label = LabelProvider.label(for: binding, in: keymap)
        recentPresses.insert(RecentPress(id: UUID(), text: label.tap, at: Date()), at: 0)
        if recentPresses.count > 6 { recentPresses.removeLast(recentPresses.count - 6) }
    }

    private func engineTick() {
        guard var engine else { return }
        engine.tick(at: Date())
        applyEngine(engine)
    }

    private func applyEngine(_ updated: InferenceEngine) {
        engine = updated
        if pinnedLayer == nil {
            if displayedLayer != updated.displayed { displayedLayer = updated.displayed }
        }
        let lit = updated.highlighted
        if highlighted != lit { highlighted = lit }
        scheduleTickIfNeeded(updated.needsTick)
    }

    // MARK: - Editing

    /// Watch the keymap file so external edits ($EDITOR, git) hot-reload the
    /// HUD. Our own atomic writes also land here — reload is idempotent.
    func startWatching() {
        fileWatcher = FileWatcher(url: Prefs.keymapURL) { [weak self] in
            guard let self else { return }
            self.loadKeymap()
            Task { await self.refreshDiff() }
        }
        Task { await refreshDiff() }
    }

    func applyEdit(position: Int, binding: KeyBinding) {
        guard let keymap else { return }
        let layer = displayedLayer
        let oldText = keymap.layers[layer].bindings[position].raw
        do {
            _ = try KeymapEditor.apply(keymap: keymap, layer: layer, position: position, with: binding)
            editingPosition = nil
            editError = nil
            editSummaries.append("\(keymap.layerName(layer))[\(position)] \(oldText) → \(binding.dtsText)")
            loadKeymap()
            regenerateCheatsheet(announce: false)
            Task { await refreshDiff() }
        } catch {
            editError = "\(error)"
        }
    }

    func refreshDiff() async {
        let diff = await pipeline.keymapDiff()
        gitDiff = diff.isEmpty ? nil : diff
        if gitDiff == nil { editSummaries = [] }
    }

    func revertEdits() {
        Task {
            let result = await pipeline.restoreKeymap()
            if !result.ok { editError = result.display }
            editSummaries = []
            loadKeymap()
            await refreshDiff()
        }
    }

    /// Regenerate the layer diagrams inside zmk-config's CHEATSHEET.md so it
    /// can never drift from the keymap. Hand-written prose stays untouched.
    @discardableResult
    func regenerateCheatsheet(announce: Bool = true) -> Bool {
        guard let keymap, !geometry.isEmpty else { return false }
        let url = URL(fileURLWithPath: Prefs.zmkConfigPath).appendingPathComponent("CHEATSHEET.md")
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            if announce { statusToast = "CHEATSHEET.md が見つかりません" }
            return false
        }
        let date = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        guard let updated = CheatsheetGenerator.regenerate(markdown: markdown, keymap: keymap,
                                                           geometry: geometry, date: date) else {
            if announce { statusToast = "CHEATSHEET.md は最新です" }
            return false
        }
        do {
            try Data(updated.utf8).write(to: url, options: .atomic)
            if announce { statusToast = "CHEATSHEET.md の配置図を再生成しました" }
            Task { await refreshDiff() }
            return true
        } catch {
            if announce { statusToast = "CHEATSHEET.md 書込失敗: \(error)" }
            return false
        }
    }

    func triggerDraw() {
        Task {
            let result = await pipeline.triggerDrawWorkflow()
            statusToast = result.ok
                ? "draw.yml を起動しました（SVG再生成）"
                : "draw.yml 起動失敗: \(result.stderr)"
        }
    }

    // MARK: - Commit → build → download pipeline

    func commitAndPush() {
        guard !pipelineState.isRunning else { return }
        Task { await runPipeline() }
    }

    private func commitMessage() -> String {
        if editSummaries.count == 1 {
            return "keymap: \(editSummaries[0]) (roba-hud)"
        }
        return "keymap: \(max(editSummaries.count, 1)) key changes (roba-hud)\n\n"
            + editSummaries.joined(separator: "\n")
    }

    private func runPipeline() async {
        pipelineLog = []
        downloadedFirmwareURL = nil
        pipelineState = .running("事前チェック中")

        let unrelated = await pipeline.unrelatedChanges()
        if !unrelated.isEmpty {
            pipelineLog.append("⚠︎ keymap 以外の変更があります（コミットしません）:\n"
                               + unrelated.joined(separator: "\n"))
        }
        guard await pipeline.ghAuthOK() else {
            pipelineState = .failed("gh 未認証です。ターミナルで gh auth login を実行してください")
            return
        }

        regenerateCheatsheet(announce: false)   // keep CHEATSHEET in the same commit
        pipelineState = .running("commit & push 中")
        let results = await pipeline.commitAndPush(message: commitMessage())
        pipelineLog += results.map(\.display)
        guard results.count == 3, results.allSatisfy(\.ok) else {
            pipelineState = .failed("git 失敗（ログ参照）")
            return
        }
        guard let sha = await pipeline.headSHA() else {
            pipelineState = .failed("HEAD の取得に失敗しました")
            return
        }
        await refreshDiff()

        pipelineState = .running("GitHub Actions のビルド待ち")
        for _ in 0..<80 {                       // 80 × 15s ≒ 20分で打ち切り
            if let run = await pipeline.findRun(sha: sha) {
                if run.status == "completed" {
                    if run.conclusion == "success" {
                        await finishDownload(run: run, sha: sha)
                    } else {
                        pipelineState = .failed("ビルド失敗 (\(run.conclusion ?? "unknown"))。Actions ページを確認してください")
                    }
                    return
                }
                pipelineState = .running("ビルド中… (\(run.status))")
            }
            try? await Task.sleep(for: .seconds(15))
        }
        pipelineState = .failed("ビルド待ちタイムアウト。Actions ページを確認してください")
    }

    private func finishDownload(run: GitPipeline.WorkflowRun, sha: String) async {
        pipelineState = .running("ファームウェアをダウンロード中")
        let (result, dest) = await pipeline.downloadArtifact(runID: run.databaseId, sha: sha)
        pipelineLog.append(result.display)
        guard result.ok else {
            pipelineState = .failed("artifact のダウンロードに失敗しました（ログ参照）")
            return
        }
        downloadedFirmwareURL = dest
        pipelineState = .succeeded("ビルド成功・UF2 ダウンロード完了")
        showFlashGuide = true
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    /// A light repeating timer runs only while the engine has decaying state.
    private func scheduleTickIfNeeded(_ needed: Bool) {
        if needed, tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.engineTick() }
            }
        } else if !needed, let timer = tickTimer {
            timer.invalidate()
            tickTimer = nil
        }
    }
}
