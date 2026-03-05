# GlideCursor

macOS 14+ 向けの慣性カーソルユーティリティ。

## 開発の再開方法

このプロジェクトは `/Users/cahier/Documents/App/glidecursor` にあります。

1. **Xcode で開く**
   - `glidecursor.xcodeproj` をダブルクリックして開きます。

2. **ビルドと実行**
   - 左上の再生ボタン（▶）を押すか、`Command + R` を押します。

3. **権限設定**
   - ビルドし直すたびに、アクセシビリティ権限の再許可が必要になる場合があります。
   - 「システム設定」>「プライバシーとセキュリティ」>「アクセシビリティ」で、`GlideCursor` のスイッチを OFF → ON にしてください。

## ファイル構成

- **App**: アプリの起動処理 (`GlideCursorApp`, `AppDelegate`)
- **Core**: コアロジック
  - `InertiaEngine.swift`: 慣性移動の計算
  - `EventTapManager.swift`: マウス入力の監視とフリック検知
  - `SettingsManager.swift`: 設定値の保存 (UserDefaults)
- **UI**: 設定画面 (`SettingsView`)、メニューバー (`MenuBarManager`)

## 注意点

- **App Sandbox**: 無効化されています（カーソル制御のため必須）。
- **Signing**: 開発中は "Sign to Run Locally" またはご自身の Apple ID を使用してください。
