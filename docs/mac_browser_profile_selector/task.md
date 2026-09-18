# macOS ブラウザプロファイル選択アプリ タスクリスト

## プランニング (PLANNING)
- [x] 実装計画（要件定義・技術スタック・コンポーネント構成）の作成
- [x] 実装計画のユーザーレビューと承認

## 実装 (EXECUTION)
- [x] プロジェクトディレクトリ（ソースコード用）の作成
- [x] `Info.plist` の作成 (URLスキームインターセプト設定等)
- [x] 設定画面UIと保存処理（`SettingsView.swift`）の実装
- [x] ブラウザプロファイル取得ロジック（`ProfileScanner.swift`）の実装
- [x] ポップアップ選択UI（`PopupView.swift`）の実装
- [x] ブラウザ・プロファイル起動処理（`BrowserLauncher.swift`）の実装
- [x] URLイベントの受付とルーティング（`URLHandler.swift`）の実装
- [x] アプリのエントリポイント・メニューバー常駐化（`App.swift`）の実装
- [x] CLIビルドスクリプト（`build.sh`）の作成と実行権限付与

## 追加実装要件のプランニング (PLANNING)
- [x] UIおよび多種ブラウザ・カスタムブラウザ追加設計のリストアップ
- [ ] ユーザーへの計画のレビューと承認

## 追加実装要件の実装 (EXECUTION)
- [x] 設定画面に追加ブラウザ登録UI（名前、アプリパスの指定）を実装
- [x] `BrowserType` と動的ブラウザリストを統合管理するモデル（`BrowserManager` 等）の実装
- [x] Chrome派生ブラウザ（Brave, Vivaldi等）、Safari, Firefox等の自動検出処理の実装
- [x] ポップアップUI (`PopupView`) の大型化・縦スクロールへのレイアウト変更
- [x] 新規ブラウザ・プロファイルを起動する `BrowserLauncher` の処理拡張
- [x] **[追加]** ログイン時に自動起動する設定項目（`SMAppService`利用）の実装

## 追加実装の検証 (VERIFICATION)
- [/] 新たに対応したブラウザへのURLの受け渡しテスト
- [ ] カスタムアプリの登録・削除および連携テスト
- [ ] 最終成果物（`walkthrough.md`）の反映
