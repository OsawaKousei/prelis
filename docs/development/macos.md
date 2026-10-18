# macOS 向けデスクトップビルド

コマンドは、指定がない限りリポジトリのルートで実行します。共通の環境と設定は[デスクトップ開発](desktop.md)を参照してください。

## 一括ビルド

```sh
./scripts/macos/build-macos.sh
```

`kousei@192.168.1.80` にソースを同期し、Mac 上で `npm ci`、Tauri の release `.app` ビルド、`.app` の ZIP 化、DMG 作成を行います。ZIP と DMG をローカルの `apps/desktop/src-tauri/target/release/bundle/` に回収し、Mac 側で作った SHA-256 一覧と照合します。SSH 鍵認証とローカルの Mutagen、OpenSSH クライアント、Python 3、`sha256sum` が必要です。

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

`kousei@192.168.1.80:prelis-remote` に Mutagen の `one-way-safe` セッション `prelis-macos` で同期します。スクリプトは同期完了・競合なし・Mac 側の `package.json` を確認します。Windows 用の SSH ラッパーを使わないよう、Mutagen のデータは `.mutagen-macos/` に分けています。

Git 管理情報、依存、ビルド生成物、Terraform 生成物、認証ファイルは同期しません。Mac 側の `node_modules` と Rust の `target` は Mac で生成して再利用します。

## Mac 側で直接ビルドする場合

Mac に Xcode 本体、Rust、Node.js と npm を用意します。この Mac では Node.js は fnm にあり、SSH の非対話シェルには Homebrew の PATH が入らず、`xcode-select` は Command Line Tools を指しています。スクリプトがインストール済みの Node.js と Xcode を選びます。

```sh
ssh kousei@192.168.1.80
cd ~/prelis-remote
bash scripts/macos/build-on-mac.sh
```

Mac 側では `.app` と、上記の ZIP・DMG・SHA-256 一覧を生成します。ソース変更後は先に同期スクリプトを再実行してください。

## 確認状況

2026-10-18 に macOS 27.0.1、Xcode 27.1、Apple Silicon、Node.js 24.22.0、Rust 1.99.1 でフロントエンドと Rust の release ビルド、arm64 の `.app`・ZIP・DMG 作成を確認しました。`unzip` と `hdiutil verify`、回収後の SHA-256 照合も通っています。起動・機能操作、Developer ID 署名、公証は未確認です。

Tauri に DMG も直接作らせると、SSH セッションでは Finder の外観設定用 AppleScript (`osascript`) が応答待ちになりました。そのため一括スクリプトは Tauri に `.app` のみ作らせ、DMG は `hdiutil` で作ります。
