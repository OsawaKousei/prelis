# デスクトップ開発

コマンドはリポジトリのルートで実行します。
先に[共通セットアップ](workflow.md)を完了してください。

## 必要な環境

- [.nvmrc](../../.nvmrc) に合わせた Node.js と npm。
- [Cargo.toml](../../apps/desktop/src-tauri/Cargo.toml) の Rust edition 2024 と依存をビルドできる stable toolchain。
- [Tauri の OS 別前提条件](https://v2.tauri.app/start/prerequisites/)に対応するネイティブ開発ツール。
  Linux では WebKitGTK 4.1・GTK 3 などの開発ライブラリが必要です。

OS 固有のインストール方法は上記の公式文書を参照してください。
このマシンでの確認結果は[環境メモ](../environment/local-linux.md)に記録しています。
Windows 11 向けの同期・ビルド手順は [Windows ビルド手順](windows.md) を参照してください。

## 開発起動

```sh
npm run dev:desktop
```

Tauri CLI が Vite と Rust アプリを起動します。
共有 core の変更は Vite がソースから取り込みます。

フロントエンドだけをブラウザーで確認する場合:

```sh
npm run dev -w apps/desktop
```

開発サーバーは `http://localhost:1420/` です。
ブラウザーだけでは Tauri のネイティブ API を使う機能の動作確認はできません。

## ビルド

```sh
# 型チェックとフロントエンドのビルド
npm run build -w apps/desktop

# debug 実行ファイル（配布パッケージ生成なし）
npm run build:desktop:debug

# release 実行ファイルと配布パッケージ
npm run build:desktop
```

| 成果物 | 既定の出力先 |
| --- | --- |
| フロントエンド | `apps/desktop/dist/` |
| debug 実行ファイル | `apps/desktop/src-tauri/target/debug/desktop`（Windows は `.exe`） |
| release 実行ファイル | `apps/desktop/src-tauri/target/release/desktop`（Windows は `.exe`） |
| 配布パッケージ | `apps/desktop/src-tauri/target/release/bundle/` |

`CARGO_TARGET_DIR` を指定した場合、Rust 側の出力先はそのディレクトリになります。
配布パッケージの形式・作成条件は実行 OS と Tauri 設定に依存します。
開発用 debug ビルドの成功は、各 OS の配布・署名検証の完了を意味しません。

## 設定の所在

| 内容 | ファイル |
| --- | --- |
| アプリ名・識別子・ウィンドウ・ビルドフック・frontendDist | [tauri.conf.json](../../apps/desktop/src-tauri/tauri.conf.json) |
| ネイティブ権限 | [capabilities/default.json](../../apps/desktop/src-tauri/capabilities/default.json) |
| Rust の依存と release 設定 | [Cargo.toml](../../apps/desktop/src-tauri/Cargo.toml) |
| Windows・Ubuntu のアプリアイコン | [共有アイコンの生成手順](../../packages/icons/README.md) |
| 開発サーバー・ポート・HMR | [vite.config.ts](../../apps/desktop/vite.config.ts) |
| UI の型チェック | [tsconfig.json](../../apps/desktop/tsconfig.json) |
| Vite 設定の型チェック | [tsconfig.node.json](../../apps/desktop/tsconfig.node.json) |

## トラブルシュート

- **ポート 1420 が使用中**: 重複した開発サーバーがないか確認します。ポート変更時は Vite の設定と Tauri の `devUrl` を一緒に更新します。
- **ブラウザーでは動くがアプリでは失敗する**: `npm run dev:desktop` で起動し、Rust 側のログと Tauri の権限・設定を確認します。
- **ネイティブライブラリが見つからない**: OS ごとの Tauri 前提条件を確認します。
- **Rust の生成済みメタデータが破損している**: 別の `CARGO_TARGET_DIR` で再ビルドし、キャッシュの問題か切り分けます。
- **core の変更が反映されない**: `@prelis/core` の `browser` 条件がソースを指しているか、起動した workspace が正しいか確認します。
