import SwiftUI

/// Step-by-step UF2 flashing instructions shown after a successful build.
struct FlashGuide: View {
    @Bindable var store: HUDStore
    @State private var showLeftHalf = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ファームウェア書き込みガイド").font(.headline)
                Spacer()
                Button("閉じる") { store.showFlashGuide = false }
                    .keyboardShortcut(.cancelAction)
            }

            Label("キーマップ変更は右手側（セントラル）だけの書き換えでOK",
                  systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                step(1, "右手側の裏のリセットボタンを素早く2回押す（ダブルタップ）")
                step(2, "Finder に「XIAO-SENSE」ドライブがマウントされる")
                step(3, "roBa_R 〜.uf2 をドライブにドラッグ＆ドロップ")
                step(4, "自動でアンマウントされ再起動。BLE は自動再接続")
            }

            if let url = store.downloadedFirmwareURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("ダウンロードフォルダを開く", systemImage: "folder")
                }
                .font(.system(size: 11))
            }

            DisclosureGroup(isExpanded: $showLeftHalf) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ZMK 本体や設定（Kconfig）が変わったときだけ、roBa_L 〜.uf2 を左手側にも同じ手順で書き込む。")
                    Text("左右で挙動がおかしくなったら settings_reset を両方に書いてから、通常ファームを書き直し、FUNC の BTclr（0.5秒ホールド）→再ペアリング。")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            } label: {
                Text("左手側 / トラブル時").font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor.opacity(0.7)))
                .foregroundStyle(.white)
            Text(text).font(.system(size: 12))
        }
    }
}
