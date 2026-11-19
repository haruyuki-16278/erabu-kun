# Erabu-kun (選ぶくん)

Erabu-kun は、リンクを開く際にどのブラウザで開くかを動的に選択・ルーティングするための macOS 向けメニューバー常駐型アプリケーションです。

配布は **Developer ID（notarized DMG）経由のみ** です。App Sandboxが必須の
Mac App Storeではプロファイル別振り分け機能が利用できないため（詳細は後述）、
本アプリはMac App Storeでは配布していません。
紹介ページ: https://erabu-kun.relicsnow.net/

## 特徴
- メニューバーに常駐し、URLを開く際のデフォルトブラウザとして動作します。
- プロファイルやルールに基づいて、適切なブラウザ（Chrome, Safari, Firefoxなど）でリンクを開き分けます。
- カスタムルールの設定が可能です。

## インストール方法

1. [Releases](https://github.com/haruyuki-16278/erabu-kun/releases/latest) ページから最新の `.dmg` ファイルをダウンロードします。
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

## Xcodeでの開発ビルドについて（Mac App Store提出は現在行っていません）

> **注記**: App Sandbox環境下では `open`/`NSWorkspace` 経由の引数渡し（`--profile-directory=`等）が
> OSレベルで無効化されるため、Mac App Store配布ではプロファイル別振り分けという
> 本アプリの主要機能が動作しません。そのため現在はMac App Store提出を行わず、
> Developer ID配布（上記のDMGビルド）のみで公開しています。
> 以下はXcodeでの開発・動作確認用のビルド手順として残しています。

[XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成するXcodeプロジェクトを使うと、
Xcode上でのデバッグ実行や将来的な再提出の検討も可能です。
`Erabukun.xcodeproj` は `project.yml` から生成されるため、リポジトリには含まれていません。

1. XcodeGenをインストールします（初回のみ）。
   ```
   brew install xcodegen
   ```
2. プロジェクトルートで以下を実行し、`Erabukun.xcodeproj` を生成します。
   ```
   xcodegen generate
   ```
3. `Erabukun.xcodeproj` をXcodeで開きます。
4. 「Signing & Capabilities」タブで自分のApple Developerアカウントのチームを選択し、
   「Automatically manage signing」が有効になっていることを確認します
   （初回はApp Store Connect側でのApp ID登録・Provisioning Profileの自動作成が行われます）。
5. Product > Archive でアーカイブを作成し、Organizerから
   「Distribute App」→「App Store Connect」を選択してアップロードします。

`src/*.swift` のソースコードはDeveloper ID配布用の `build_release.sh` と
共有しているため、どちらの方法でビルドしても同じ機能が反映されます。
`project.yml` を変更した場合は、必ず `xcodegen generate` を再実行してください。

## CI（GitHub Actions）でのビルドについて

`main` ブランチへの push、タグの push、または手動実行（`workflow_dispatch`）で、
`.github/workflows/build-and-release.yml` が macOS ランナー上でビルド・署名・
公証・DMG化までを自動実行し、成果物として `Erabu-kun.dmg` をアーティファクトに
アップロードします。**main へのマージ・push だけではリリースを公開しません。**

公開するときは GitHub の **Actions → Build, Sign, and Package DMG → Run workflow** で、
ブランチに `main` を選び、**release** にチェックを入れて実行してください。
既定値はオフで、チェックを入れない実行はビルドとアーティファクトの保存だけを行います。
誤公開を防ぐため、`main` 以外を指定して `release` をオンにした実行はエラーになります。

リリースは CalVer を使い、タグを `vYYYY.MM.DD-実行番号`（例: `v2026.11.19-42`）として
自動作成します。日付はワークフロー実行の作成日時の UTC 日付、実行番号は
`github.run_number` です。同日に複数回公開でき、同じ実行の再実行では同じタグを使います。
タグは実行対象のコミットに固定され、既存タグが別のコミットを指している場合は停止します。

アプリの `CFBundleShortVersionString` は実行番号を含まない `YYYY.MM.DD` です。
ビルド番号（`CFBundleVersion`）には git のコミット数を使います。同じコミットの再実行では
ビルド番号も同じになります。`src/Info.plist` は変更せず、配布用にコピーした plist だけに
バージョンを設定するため、リリース時の手動更新は不要です。Xcode の開発ビルドでは
引き続き `src/Info.plist` の静的な値を使います。

公開しないブランチ上のビルドはビルド時点の UTC 日付を使います。既存の
`vYYYY.MM.DD` または `vYYYY.MM.DD-正の実行番号` タグ上のビルドはタグの日付を使います。
不正な形式や存在しない日付はビルド前に拒否します。**タグの push だけでも公開しません。**

署名・公証・DMG 作成に成功してから
[GitHub Release](https://github.com/haruyuki-16278/erabu-kun/releases) を作成し、その後
[紹介ページ](https://erabu-kun.relicsnow.net/) の表示バージョンと DMG ダウンロードリンクを
更新します。`gh-pages` ブランチの独自ドメイン設定、画像、プライバシーページは維持します。
Pages の更新と最新リリースへの昇格は直列化し、遅れて完了した古い実行で巻き戻さないようにします。
`GITHUB_TOKEN` の push だけに頼らず、Pages ビルドも API で明示的に要求します。

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
