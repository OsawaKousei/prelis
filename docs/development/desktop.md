# デスクトップ開発

コマンドはリポジトリのルートで実行します。環境条件と実行ファイルの例は Ubuntu（amd64）向けです。

## 環境準備

Node.js・npm の準備と依存管理は [共通セットアップ](architecture.md#共通セットアップ)を参照してください。デスクトップ固有の条件は次のとおりです。

- Rust edition 2024 と依存をビルドできる stable toolchain。
- Ubuntu では WebKitGTK 4.1・GTK 3・GStreamer の開発ライブラリと、`gstreamer1.0-plugins-base`・`gstreamer1.0-plugins-good`・`gstreamer1.0-plugins-bad`。音声再生には GStreamer の `appsink` が必要です。
- 配布用ビルドは amd64 を使用します。現在の配布スクリプトは amd64 の成果物名を前提とし、arm64 は未検証です。AppImage も glibc に依存するため、サポートする最も古い Ubuntu をビルド環境の基準にします。

## 開発起動と動作確認用ビルド

```sh
npm run dev:desktop
```

Tauri CLI が Vite と Rust アプリを起動します。

フロントエンドだけをブラウザーで確認する場合は、次を実行して `http://localhost:1420/` を開きます。

```sh
npm run dev -w apps/desktop
```

ファイル操作など Tauri のネイティブ API を使う機能は、アプリで確認します。

| コマンド | 内容 | 既定の出力先 |
| --- | --- | --- |
| `npm run build -w apps/desktop` | TypeScript の型チェックと Vite ビルド | `apps/desktop/dist/` |
| `npm run build:desktop:debug` | 配布パッケージを作らず debug 実行ファイルを生成 | `apps/desktop/src-tauri/target/debug/desktop` |
| `npm run build:desktop` | release 実行ファイルと配布パッケージを生成 | 実行ファイルは `apps/desktop/src-tauri/target/release/PrelisDesktop`、パッケージは同じ階層の `bundle/` |

`npm run build:desktop` は分離署名の作成・検証を行いません。頒布用の deb・AppImage は [Linux 配布物のビルド・署名手順](dist/linux/sign.md)に従います。

## バージョンを揃える

リリースするデスクトップ版のバージョンを、次の設定・ロックファイル・画面表示で揃えます。

| ファイル | 更新する項目 |
| --- | --- |
| [apps/desktop/src-tauri/tauri.conf.json](../../apps/desktop/src-tauri/tauri.conf.json) | `version` |
| [apps/desktop/src-tauri/Cargo.toml](../../apps/desktop/src-tauri/Cargo.toml) | `package.version` |
| [apps/desktop/package.json](../../apps/desktop/package.json) | `version` |
| [apps/desktop/src-tauri/Cargo.lock](../../apps/desktop/src-tauri/Cargo.lock) | `name = "desktop"` のパッケージの `version` |
| [package-lock.json](../../package-lock.json) | `packages["apps/desktop"].version` |
| [apps/desktop/src/shell/sidebar.tsx](../../apps/desktop/src/shell/sidebar.tsx) | サイドバー下部の `v<version>` 表示 |

ビルド後はサイドバーの表示がリリースするバージョンと一致することを確認します。
Linux の配布スクリプトはデスクトップの `package.json` の値を成果物名の確認に使います。

## 検証

[共通チェック](architecture.md#共通セットアップ)とフロントエンドのビルドを実行し、変更箇所を Tauri アプリで確認します。配布時の署名検証・インストール確認は [Linux 配布物のビルド・署名手順](dist/linux/sign.md#2-成果物と署名を確認する)を参照してください。

## 設定の所在とアイコン更新

| 内容 | ファイル |
| --- | --- |
| アプリ名・識別子・ウィンドウ・ビルドフック・フロントエンド出力先 | `apps/desktop/src-tauri/tauri.conf.json` |
| Linux の実行ファイル名・ランチャー用アイコン名 | `apps/desktop/src-tauri/tauri.linux.conf.json` |
| macOS の配布先別設定 | `apps/desktop/src-tauri/tauri.appstore.conf.json`・`tauri.github.conf.json` |
| ネイティブ API の権限とファイルアクセス範囲 | `apps/desktop/src-tauri/capabilities/default.json` |
| Rust の依存・release 最適化 | `apps/desktop/src-tauri/Cargo.toml`・`Cargo.lock` |
| 開発サーバー・ポート・HMR | `apps/desktop/vite.config.ts` |

Ubuntu 版は `tauri.conf.json` に `tauri.linux.conf.json` をマージし、バージョンは共通設定から引き継ぎます。アイコンの更新・生成は [共有アイコン](../../packages/icons/README.md)を参照してください。

## トラブルシュート

| 症状 | 確認・対処 |
| --- | --- |
| ポート 1420 が使用中 | 重複した開発サーバーを終了します。ポートを変更する場合は `vite.config.ts` の `server.port`、`tauri.conf.json` の `build.devUrl` と `app.security.devCsp` 内の開発用 URL を揃えます |
| ブラウザーでは動くがアプリでは失敗する | `npm run dev:desktop` で再現し、ターミナルの Rust ログ、WebView のエラー、`capabilities/default.json` の権限、Tauri の CSP を確認します |
| WebKitGTK・GTK・GStreamer が見つからない | `pkg-config --modversion webkit2gtk-4.1 gtk+-3.0 gstreamer-1.0` と `gst-inspect-1.0 appsink` で依存を確認します |
| Rust の生成済みメタデータが破損している | `CARGO_TARGET_DIR=/tmp/prelis-linux-debug npm run build:desktop:debug` で別の出力先にビルドし、キャッシュが原因か切り分けます。配布スクリプトを実行するときは既定の出力先に戻します |

配布物・署名・AppImage の問題は [Linux 配布物のトラブルシュート](dist/linux/sign.md#トラブルシュート)を参照してください。
