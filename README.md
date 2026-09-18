# Erabu-kun (選ぶくん)

Erabu-kun は、リンクを開く際にどのブラウザで開くかを動的に選択・ルーティングするための macOS 向けメニューバー常駐型アプリケーションです。

## 特徴
- メニューバーに常駐し、URLを開く際のデフォルトブラウザとして動作します。
- プロファイルやルールに基づいて、適切なブラウザ（Chrome, Safari, Firefoxなど）でリンクを開き分けます。
- カスタムルールの設定が可能です。

## インストール方法

1. [Releases] ページから最新の `.dmg` ファイルをダウンロードします。
2. ダウンロードした `.dmg` ファイルをダブルクリックして開きます。
3. 開いたウィンドウ内で、`Erabu-kun.app` のアイコンを右側の `Applications`（アプリケーション）フォルダのアイコンにドラッグ＆ドロップしてください。
4. インストールが完了したら、`Applications` フォルダから `Erabu-kun.app` を起動できます。

初回起動時に「開発元が未確認」などの警告が出た場合は、システム設定の「プライバシーとセキュリティ」から「開く」を許可してください（または右クリックから「開く」を選択）。

## 使い方

- 起動後、メニューバーに Erabu-kun のアイコンが表示されます。
- macOSの「デフォルトブラウザ」として Erabu-kun を設定することで、あらゆるリンククリックを Erabu-kun が中継し、設定されたルールに従ってブラウザに振り分けます。
- メニューバーのアイコンをクリックし、「Settings...」からルーティングルールやパスを設定できます。
- Chrome系ブラウザ（Chrome, Edge, Brave, Vivaldi等）のプロファイル一覧・アイコンを利用するには、
  「Settings...」の **Data Access** タブから、対象ブラウザのプロファイルデータフォルダへの
  アクセスを一度だけ許可してください。App Sandbox対応のため、ユーザーの明示的な許可なしには
  他アプリのデータへアクセスしません。一度許可すれば、後から追加されたプロファイルも自動的に
  読み込まれます（フォルダへのアクセス許可のため、再許可は不要です）。

## 開発ビルドについて

ご自身で手元でビルド・パッケージングを行いたい場合は、以下の手順を実施します。

1. リポジトリをクローンします。
2. ディレクトリ内に `.env` ファイルを作成し、Apple ID とアプリ固有パスワードを記載します。
   ```
   APPLE_ID=your.apple.id@example.com
   APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
   ```
3. `./build_release.sh` を実行します。
4. ビルド、署名、DMG化、公証（Notarization）まで全て自動で行われます。
5. 完成したパッケージは `build/Erabu-kun.dmg` に生成されます。

## CI（GitHub Actions）でのビルドについて

`main` ブランチへの push、または手動実行（`workflow_dispatch`）で、
`.github/workflows/build-and-release.yml` が macOS ランナー上でビルド・署名・
公証・DMG化までを自動実行し、成果物として `Erabu-kun.dmg` をアーティファクトに
アップロードします。

CIを動かすには、リポジトリの **Settings > Secrets and variables > Actions** で
以下のSecretsを事前に登録してください（秘密鍵を含むため、これらはご自身で
用意・登録する必要があります）。

| Secret名 | 内容 |
|---|---|
| `APPLE_ID` | 公証に使うApple ID |
| `APP_SPECIFIC_PASSWORD` | 上記Apple IDのアプリ専用パスワード |
| `DEVELOPER_ID_APPLICATION_P12` | `Developer ID Application` 証明書を `.p12` でエクスポートし、base64エンコードした文字列（`base64 -i cert.p12 \| pbcopy` など） |
| `DEVELOPER_ID_APPLICATION_PASSWORD` | 上記 `.p12` ファイルのエクスポート時に設定したパスワード |
| `KEYCHAIN_PASSWORD` | CI実行中にのみ使う一時キーチェーンのパスワード（任意の文字列で可） |

証明書はキーチェーンアクセスで対象の証明書と秘密鍵を選択し、「書き出す」から
`.p12` 形式でエクスポートできます。
