# macOS 向けデスクトップビルド

コマンドは、指定がない限りリポジトリのルートで実行します。共通の環境と設定は[デスクトップ開発](desktop.md)を参照してください。

## Mac App Store 向け署名済み App

```sh
# 初回のみ
cp scripts/macos/.env.example scripts/macos/.env
chmod 600 scripts/macos/.env
# scripts/macos/.env に PRELIS_APPSTORE_P12_PASSWORD を記入
./scripts/macos/build-appstore.sh
```

`kousei@192.168.10.22` へソースを同期し、Apple Distribution の既存 `.p12` を一時キーチェーンに読み込みます。ローカルの `scripts/macos/.env` をシェルとして実行せず、`PRELIS_APPSTORE_P12_PASSWORD` だけを読み込みます。環境変数が設定されている場合はそちらを優先し、パスワードを SSH の標準入力で Mac へ渡します。`.env` は Git 管理と Mac 同期から除外し、権限 `0600` を必須とします。Mac 側で直接スクリプトを実行する場合は、従来どおりパスワード入力を求めます。

Mac のホームに `KUPACLLC-Apple-Distribution.p12` と `kupacprelisdesktopmacosappstore.provisionprofile` が必要です。`.p12` の権限は `0600` にします。Apple WWDR G3 中間証明書を Mac のログインキーチェーンへインストールしておきます。ビルド後、一時キーチェーンは削除されます。

一時キーチェーンへの証明書の読み込みと秘密鍵の署名アクセス設定は、[Tauri の CI 向け署名手順](https://v2.tauri.app/distribute/sign/macos/#signing-in-cicd-platforms)と同じ方式です。スクリプトは実行中だけ既定キーチェーンと検索先を切り替え、終了時に元へ戻します。

Mac 側では `tauri.appstore.conf.json` を重ね、Bundle ID `jp.co.kupac.prelis`、App Sandbox、ネットワーククライアント権限、埋め込み Provisioning Profile を適用します。通常のデスクトップ設定の Bundle ID は変えません。`codesign --verify --deep --strict`、署名 Entitlements、Bundle ID、埋め込み Profile を確認してから ZIP を回収し、SHA-256 を照合します。

| 成果物 | 出力先 |
| --- | --- |
| 署名済み `.app` | Mac: `~/prelis-remote/apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app` |
| 回収した `.app` の ZIP | ローカル: `apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_<version>_<arch>_appstore.app.zip` |

`apps/desktop/src-tauri/signing/` は Git 管理と Mac 同期から除外します。Profile は Mac のホームからビルド時にコピーします。App Store Connect のアプリ登録、暗号化輸出規制の申告内容、Sandbox 内での機能操作、提出用 `.pkg` の作成とアップロードは別途確認が必要です。

2026-10-29 に macOS 27.0.1、Xcode 27.1、Apple Silicon で `0.1.1` の署名済み `.app` を作成しました。`scripts/macos/.env` を読み込む非対話ビルドでも再生成しています。`codesign --verify --deep --strict`、App Sandbox と App ID の Entitlements、Bundle ID、埋め込み Profile、回収後の SHA-256 照合が通っています。アプリの起動・機能操作と App Store Connect への提出は今回未確認です。

## 一括ビルド

```sh
./scripts/macos/build-macos.sh
```

`kousei@192.168.10.22` にソースを同期し、Mac 上で `npm ci`、Tauri の release `.app` ビルド、`.app` の ZIP 化、DMG 作成を行います。ZIP と DMG をローカルの `apps/desktop/src-tauri/target/release/bundle/` に回収し、Mac 側で作った SHA-256 一覧と照合します。SSH 鍵認証とローカルの Mutagen、OpenSSH クライアント、Python 3、`sha256sum` が必要です。

| 成果物 | ローカルの出力先 |
| --- | --- |
| アプリの ZIP | `apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop_<version>_<arch>.app.zip` |
| DMG | `apps/desktop/src-tauri/target/release/bundle/dmg/PrelisDesktop_<version>_<arch>.dmg` |
| SHA-256 一覧 | `apps/desktop/src-tauri/target/release/bundle/macos-artifacts.sha256` |

現在のビルドは Developer ID 署名と公証を行いません。DMG は Finder の外観設定を省き、`hdiutil` で作成します。アプリと `Applications` へのリンクが入ります。ダウンロードして配布した場合の Gatekeeper の通過は確認していません。

## 同期のみ実行する場合

```sh
./scripts/macos/create-macos-sync.sh
```

`kousei@192.168.10.22:prelis-remote` に Mutagen の `one-way-safe` セッション `prelis-macos` で同期します。スクリプトは同期完了・競合なし・必要ファイルの存在と不要ディレクトリの不在を確認します。Windows 用の SSH ラッパーを使わないよう、Mutagen のデータは `.mutagen-macos/` に分けています。

同期対象はルートの npm 定義、`apps/desktop`、`packages/core`、`packages/icons`、Mac 側のビルドスクリプトです。Android・iOS・ウェブのアプリ、インフラ、LP、ドキュメント、他 OS のスクリプト、アイコン生成スクリプト、サンプル画像、Git 管理情報、依存、`*.tsbuildinfo` と `src-tauri/gen` を含むビルド生成物、認証ファイルは除外します。Mac 側の `node_modules` と Rust の `target` は Mac で生成して再利用します。

2026-10-30 に同期先を削除してから再作成し、86 ファイル・1.2 MB、競合 0 件を確認しました。この同期先から `npm ci` は 39 パッケージを導入し、App Store 向けの署名済み `.app` を再ビルドしています。

## Mac 側で直接ビルドする場合

Mac に Xcode 本体、Rust、Node.js と npm を用意します。この Mac では Node.js は fnm にあり、SSH の非対話シェルには Homebrew の PATH が入らず、`xcode-select` は Command Line Tools を指しています。スクリプトがインストール済みの Node.js と Xcode を選びます。

```sh
ssh kousei@192.168.10.22
cd ~/prelis-remote
bash scripts/macos/build-on-mac.sh
```

Mac 側では `.app` と、上記の ZIP・DMG・SHA-256 一覧を生成します。ソース変更後は先に同期スクリプトを再実行してください。

## 確認状況

2026-10-18 に macOS 27.0.1、Xcode 27.1、Apple Silicon、Node.js 24.22.0、Rust 1.99.1 でフロントエンドと Rust の release ビルド、arm64 の `.app`・ZIP・DMG 作成を確認しました。`unzip` と `hdiutil verify`、回収後の SHA-256 照合も通っています。起動・機能操作、Developer ID 署名、公証は未確認です。

Tauri に DMG も直接作らせると、SSH セッションでは Finder の外観設定用 AppleScript (`osascript`) が応答待ちになりました。そのため一括スクリプトは Tauri に `.app` のみ作らせ、DMG は `hdiutil` で作ります。
