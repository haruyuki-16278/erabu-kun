# Erabu-kun (選ぶくん)

Erabu-kun は、リンクを開く際にどのブラウザで開くかを動的に選択・ルーティングするための macOS 向けメニューバー常駐型アプリケーションです。

配布は **Developer ID（notarized DMG）経由のみ** です。App Sandboxが必須の
Mac App Storeではプロファイル別振り分け機能が利用できないため（詳細は後述）、
本アプリはMac App Storeでは配布していません。
紹介ページ: https://haruyuki-16278.github.io/erabu-kun/

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

`main` ブランチへの push、または手動実行（`workflow_dispatch`）で、
`.github/workflows/build-and-release.yml` が macOS ランナー上でビルド・署名・
公証・DMG化までを自動実行し、成果物として `Erabu-kun.dmg` をアーティファクトに
アップロードします。

さらに `v*` 形式のタグ（例: `v1.0.1`）をpushすると、同じワークフローが
DMGを添付した [GitHub Release](https://github.com/haruyuki-16278/erabu-kun/releases)
を自動作成します。新しいバージョンを公開する際は、`src/Info.plist` の
`CFBundleShortVersionString` を更新した上で以下のようにタグを打ってください。

```
git tag -a v1.0.2 -m "v1.0.2"
git push origin v1.0.2
```

紹介用のランディングページ（`gh-pages` ブランチ、
https://haruyuki-16278.github.io/erabu-kun/ ）は最新Releaseへ自動リンクしているため、
リリースを作成するだけでダウンロードリンクも更新されます。

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
