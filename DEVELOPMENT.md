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
│   ├── GlideController.swift     # 司令塔：イベントタップ、フリック判定、停止、クリック抑止
│   ├── Multitouch.swift          # MultitouchSupport（非公開）で指の接触・離脱を取る
│   ├── DeviceRegistry.swift      # CGEvent の送信元 → デバイス（永続キー）の対応付け
│   ├── InertiaEngine.swift       # 慣性移動（120Hz タイマー、指数減衰）
│   ├── SettingsManager.swift     # 設定値の保存・読み込み（UserDefaults）
│   └── HotKeyManager.swift       # グローバルショートカットの登録（Carbon HotKey API）
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
| `GlideController.swift` | `CGEventTap` でカーソル移動を送信元ごとに記録。MT の「離した」を受けて直前 60ms の速度で慣性を開始し、「触れた」で即停止。停止に使ったタップのクリックを捨てる |
| `Multitouch.swift` | `MultitouchSupport.framework` を `dlopen` で読み、デバイスごとの接触本数・接触の開始と終了を追う。接続・切断とスリープ復帰で一覧を取り直す |
| `DeviceRegistry.swift` | `CGEventCopyIOHIDEvent` + `IOHIDEventGetSenderID` で得た送信元（IORegistry entry ID）を、再接続しても変わらない永続キー（`mt:<Multitouch ID>`）へ対応付ける |
| `InertiaEngine.swift` | 慣性移動。速度は px/秒、減衰は時定数。`stop()` は任意スレッドから呼べ、戻った後は移動を 1 つも出さない |
| `SettingsManager.swift` | 設定値（`v2.` 付きキー）とデバイスごとの有効／無効を `UserDefaults` に保存 |
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

### 指の接触の検出（MultitouchSupport）
非公開フレームワークのため、OS 更新で構造体レイアウトが変わる可能性がある。起動時に `MTFinger` の stride（96）を確かめ、合わなければ MT を使わない（設定画面に警告を出す）。指が触れた通知は、最初のカーソル移動より 20〜40ms 早く届く。

### デバイスの判別
カーソル移動の `CGEvent` から `CGEventCopyIOHIDEvent` → `IOHIDEventGetSenderID` で送信元の IORegistry entry ID を得る。これは MT デバイスのサービスの entry ID と一致する。entry ID は再接続で変わるので、設定は `Multitouch ID`（`MTDeviceGetDeviceID`）で保存する。Magic Mouse は family 112、トラックパッドはそれ以外。送信元 0 はシステムが作ったイベントなので無視する。タッチセンサーのないマウスは対象外。

### フリック判定
1 本指の接触が離れた 12ms 後に、その送信元の直前 60ms のカーソル移動から速度を求める。最後の移動が離す 40ms より前なら（指を止めてから離した）慣性を出さない。ドラッグ中、2 本指以上は対象外。

### 停止
任意の MT デバイスへの接触、他のデバイスからの移動、クリック、スクロールで止める。慣性を始めたトラックパッドから離した直後（150ms 以内、指なし）に届く移動は、止めずに慣性の起点をずらす。

### クリック抑止
tap to click では、指が離れて 2〜4ms 後にクリックが届く。慣性を止めた接触が離れてから 150ms 以内の mouseDown を捨て、対応する mouseUp も捨てる。押し込みクリック（指が触れている間の mouseDown）は通す。

### ログ
判定の理由は `log stream --predicate 'subsystem == "jp.yaoyorozu.glidecursor"' --level debug` で見られる。

---

## Signing（署名）

開発中は Xcode の **Signing & Capabilities** で以下のいずれかを選択してください。

- **Sign to Run Locally** — Apple Developer Program 未加入でも動作する
- 個人の **Apple Developer アカウント** を使用する

配布用（.pkg）には **Developer ID Application** および **Developer ID Installer** 証明書が必要です。
