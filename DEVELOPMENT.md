# GlideCursor — 開発者ドキュメント

---

## プロジェクトのセットアップ

リポジトリをクローンし、`GlideCursor.xcodeproj` を Xcode で開いてください。

```bash
git clone <repository-url>
open GlideCursor.xcodeproj
```

**動作要件**

- macOS 14 Sonoma 以降
- Xcode 15 以降

---

## ビルドと実行

Xcode のツールバーにある **▶（実行）** ボタンを押すか、`Command + R` でビルド・起動します。

初回起動時は、システム設定でアクセシビリティ権限を付与してください。

---

## アクセシビリティ権限について

GlideCursor はカーソル制御のために **アクセシビリティ権限** が必要です。

Xcode でビルドし直したり、署名が変わったりすると権限が無効になることがあります。その際は以下の手順で再許可してください。

1. **システム設定 → プライバシーとセキュリティ → アクセシビリティ** を開く
2. GlideCursor のスイッチを **OFF → ON** に切り替える

---

## ディレクトリ構成

```
glidecursor/
├── App/
│   ├── GlideCursorApp.swift      # @main エントリポイント
│   └── AppDelegate.swift         # 起動処理・権限チェック・多重起動防止
│
├── Core/
│   ├── InertiaEngine.swift       # 慣性移動の計算（CVDisplayLink）
│   ├── EventTapManager.swift     # マウス入力の監視・フリック検知（CGEventTap）
│   ├── SettingsManager.swift     # 設定値の保存・読み込み（UserDefaults）
│   ├── HotKeyManager.swift       # グローバルショートカットの登録（Carbon HotKey API）
│   └── HIDDeviceManager.swift    # デバイス情報の取得（将来の拡張用）
│
└── UI/
    ├── MenuBarManager.swift      # ステータスバーアイコン・NSPopover 管理
    ├── SettingsView.swift        # メニューバー内の設定画面（SwiftUI）
    └── FirstLaunchView.swift     # 初回起動ウェルカム画面（SwiftUI）
```

---

## 主要コンポーネントの役割

### App

| ファイル | 役割 |
|---|---|
| `GlideCursorApp.swift` | SwiftUI `@main`。`AppDelegate` をアダプタで接続する |
| `AppDelegate.swift` | 起動シーケンス（権限確認 → 初回フロー → EventTap 開始）、スリープ対応、多重起動防止 |

### Core

| ファイル | 役割 |
|---|---|
| `InertiaEngine.swift` | `CVDisplayLink` を使ったフレーム単位の慣性計算と `CGEvent` によるカーソル移動 |
| `EventTapManager.swift` | `CGEventTap`（`.cghidEventTap`）でマウスイベントをキャプチャし、フリック速度を計算して `InertiaEngine` に渡す |
| `SettingsManager.swift` | `ObservableObject`。設定値を `UserDefaults` に永続化し、`HotKeyManager` と連携する |
| `HotKeyManager.swift` | Carbon の `RegisterEventHotKey` API でグローバルショートカットを登録する |

### UI

| ファイル | 役割 |
|---|---|
| `MenuBarManager.swift` | `NSStatusItem` と `NSPopover` の管理。外クリック検知（`NSEvent.addGlobalMonitorForEvents`）を含む |
| `SettingsView.swift` | スライダー・トグル・ショートカット設定を含む設定 UI |
| `FirstLaunchView.swift` | 初回起動時のオンボーディング画面 |

---

## 技術的な注意点

### App Sandbox
無効化されています（`com.apple.security.app-sandbox` エンタイトルメントなし）。カーソル制御には `CGEventTap` が必要なため、Sandbox との共存は不可能です。

### CGEventTap
`.cghidEventTap` + `.headInsertEventTap` + `.defaultTap` の組み合わせで動作します。アクセシビリティ権限がないと `tapCreate` が `nil` を返します。

### フリック検知
`checkFlick()` は 16ms 間隔のタイマー（watchdog）で動作します。直近5フレームの速度平均がしきい値を超えた時点でグライドを開始します。

### スクロール割り込み
`kCGScrollWheelEventScrollPhase` の `mayBegin (32)` と `began (1)` を検知し、2本指スクロール開始時にグライドを即停止します。

### グライド停止タップの抑止（実験的）
設定で有効にすると、グライド中の `leftMouseDown` をキャンセルします。`stopTapPending` フラグで対応する `mouseUp` も抑止し、タイムアウト（300ms）・右クリック・ドラッグによるフラグクリアで安全性を確保しています。

---

## Signing（署名）

開発中は Xcode の **Signing & Capabilities** で以下のいずれかを選択してください。

- **Sign to Run Locally** — Apple Developer Program 未加入でも動作する
- 個人の **Apple Developer アカウント** を使用する

配布用（.pkg）には **Developer ID Application** および **Developer ID Installer** 証明書が必要です。
