# デスクトップ開発

デスクトップアプリの環境準備、開発起動、ビルド、バージョン更新、動作確認をまとめます。
環境準備と実行ファイルの例は Ubuntu（amd64）を対象とします。
コマンドは、特記がない限り取得済みのリポジトリのルートで実行します。GUI の動作確認にはデスクトップセッションが必要です。
依存パッケージ、Node.js、Rust の取得にはネットワーク接続を使います。
署名付き deb・AppImage の作成と頒布は [Linux 配布物のビルド・署名手順](dist/linux/sign.md)を参照してください。

## 環境準備

共通の依存管理と初回セットアップは [architecture.md](architecture.md#共通セットアップ)を参照してください。
ローカルマシンの OS・ツールのバージョン・導入先・導入済みの基本 APT パッケージは [local-linux.md](../environment/local-linux.md)にまとめています。

### Ubuntu とネイティブ依存

配布先と同じ amd64 の Ubuntu を使用します。現在のスクリプトは amd64 の成果物名を前提とし、arm64 は未検証です。
AppImage も glibc などの制約を受けるため、サポートする最も古い Ubuntu をビルド環境の基準にします。新しい Ubuntu で作った成果物が古い Ubuntu で動くとは限りません。

```sh
dpkg --print-architecture
```

出力が `amd64` であることを確認します。
新しい環境では、まず [local-linux.md の基本 APT パッケージ](../environment/local-linux.md)を導入してください。
それに加え、以下の補助ツール、GTK 3、音声用の GStreamer を用意します。ローカル環境メモの導入済み一覧だけでは、配布ビルドに必要な依存がすべて揃っているとは限りません。

```sh
sudo apt update
sudo apt install \
  pkg-config unzip ca-certificates libgtk-3-dev \
  libgstreamer1.0-dev gstreamer1.0-tools \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  dpkg coreutils

pkg-config --modversion webkit2gtk-4.1 gtk+-3.0 gstreamer-1.0
gst-inspect-1.0 appsink
```

タイマーの動作確認では、終了音が再生できることも確認します。

### fnm の導入と共通セットアップ

fnm が未導入の場合は、次のコマンドで導入します。シェルの設定は次の手順で行います。

```sh
curl -fsSL https://fnm.vercel.app/install -o /tmp/prelis-fnm-install.sh
bash /tmp/prelis-fnm-install.sh --install-dir "$HOME/.local/share/fnm" --skip-shell
```

zsh を使用する場合は、以下を `~/.zshrc` に追加し、現在のシェルでも実行します。既に同じ設定がある場合は追加不要です。

```sh
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell zsh)"
```

bash を使用する場合は、以下を `~/.bashrc` に追加し、現在のシェルでも実行します。

```sh
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell bash)"
```

fnm を使える状態にしたら、[共通の初回セットアップ](architecture.md#初回セットアップ)に従い、Node.js の選択、npm 依存のインストール、共通チェックを実行します。
Node.js・npm の要件と workspaces・lockfile の管理方法は [architecture.md の依存管理](architecture.md#依存管理)を参照してください。

### Rust

`apps/desktop/src-tauri/Cargo.toml` は Rust edition 2024 を使用します。これと依存をビルドできる stable toolchain を rustup で用意します。
rustup が未導入の場合は次を実行します。

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/prelis-rustup-init.sh
sh /tmp/prelis-rustup-init.sh --profile minimal --default-toolchain stable
. "$HOME/.cargo/env"
```

rustup を導入済みの場合は `rustup toolchain install stable` で stable toolchain を用意します。
次のコマンドで、このプロジェクトで stable を使用するよう指定し、バージョンを確認します。

```sh
rustup override set stable
rustc --version
cargo --version
```

## 開発起動と動作確認用ビルド

```sh
npm run dev:desktop
```

Tauri CLI が Vite と Rust アプリを起動します。終了する場合はターミナルで `Ctrl+C` を押します。
共有ロジック `@prelis/core` のソース解決とビルドが必要になる条件は、[architecture.md](architecture.md) の「依存管理」「依存の追加・更新」を参照してください。

フロントエンドだけをブラウザーで確認する場合は、次を実行して `http://localhost:1420/` を開きます。

```sh
npm run dev -w apps/desktop
```

ブラウザーでは Tauri のネイティブ API を使う機能を確認できません。ファイル操作などの動作確認には `npm run dev:desktop` を使います。

| コマンド | 内容 | 既定の出力先 |
| --- | --- | --- |
| `npm run build -w apps/desktop` | TypeScript の型チェックと Vite ビルド | `apps/desktop/dist/` |
| `npm run build:desktop:debug` | 配布パッケージを作らず debug 実行ファイルを生成 | `apps/desktop/src-tauri/target/debug/desktop` |
| `npm run build:desktop` | release 実行ファイルと配布パッケージを生成 | 実行ファイルは `apps/desktop/src-tauri/target/release/PrelisDesktop`、パッケージは同じ階層の `bundle/` |

debug ビルドの実行ファイルは `./apps/desktop/src-tauri/target/debug/desktop` で起動できます。
`npm run build:desktop` は汎用の Tauri ビルドで、分離署名の作成・検証処理は実行しません。直接頒布する deb・AppImage は [Linux 配布物のビルド・署名手順](dist/linux/sign.md)に従って作成します。
debug の成功に加え、配布パッケージごとの署名検証とインストール後の動作確認が必要です。

## バージョンを揃える

リリースするデスクトップ版のバージョンを、次の設定・ロックファイル・画面表示で揃えます。
例えば v0.1.2 では、各バージョンの値を `0.1.2`、画面表示を `v0.1.2` にします。

| ファイル | 更新する項目 |
| --- | --- |
| [apps/desktop/src-tauri/tauri.conf.json](../../apps/desktop/src-tauri/tauri.conf.json) | `version` |
| [apps/desktop/src-tauri/Cargo.toml](../../apps/desktop/src-tauri/Cargo.toml) | `package.version` |
| [apps/desktop/package.json](../../apps/desktop/package.json) | `version` |
| [apps/desktop/src-tauri/Cargo.lock](../../apps/desktop/src-tauri/Cargo.lock) | `name = "desktop"` のパッケージの `version` |
| [package-lock.json](../../package-lock.json) | `packages["apps/desktop"].version` |
| [apps/desktop/src/shell/sidebar.tsx](../../apps/desktop/src/shell/sidebar.tsx) | サイドバー下部の `v<version>` 表示 |

`Cargo.toml`・`apps/desktop/package.json` を更新したら、対応するロックファイルの更新も差分に含めます。
ビルド後はサイドバーの表示がリリースするバージョンと一致することを確認します。
Linux の配布スクリプトはデスクトップの `package.json` の値を成果物名の確認に使います。

Ubuntu 版は共通の `tauri.conf.json` に `tauri.linux.conf.json` をマージします。
`tauri.linux.conf.json` は Linux 用の実行ファイル名を指定し、バージョンは共通設定から引き継ぎます。
`tauri.appstore.conf.json`・`tauri.github.conf.json` は macOS 用の追加設定です。

## 検証

```sh
npm run check
npm run build -w apps/desktop
```

`npm run check` の確認範囲は [共通セットアップ](architecture.md#共通セットアップ)を参照してください。
フロントエンドと Tauri アプリで動作を確認した後、[Linux 配布物のビルド・署名手順](dist/linux/sign.md)で配布パッケージを作成し、インストール後の動作を確認します。

## 設定の所在とアイコン更新

次のパスはすべてリポジトリのルートからの相対パスです。

| 内容 | ファイル |
| --- | --- |
| アプリ名・識別子・ウィンドウ・ビルドフック・フロントエンド出力先 | `apps/desktop/src-tauri/tauri.conf.json` |
| Linux の実行ファイル名・ランチャー用アイコン名 | `apps/desktop/src-tauri/tauri.linux.conf.json` |
| ネイティブ API の権限とファイルアクセス範囲 | `apps/desktop/src-tauri/capabilities/default.json` |
| Rust の依存・release 最適化 | `apps/desktop/src-tauri/Cargo.toml`・`Cargo.lock` |
| 開発サーバー・ポート・HMR | `apps/desktop/vite.config.ts` |
| UI の型チェック | `apps/desktop/tsconfig.json` |
| Vite 設定の型チェック | `apps/desktop/tsconfig.node.json` |
| 共通コマンド・npm workspaces | `package.json` |
| デスクトップのコマンド・依存 | `apps/desktop/package.json` |
| core の公開エントリ・環境別 exports | `packages/core/package.json` |
| 署名付き deb・AppImage の作成 | `scripts/linux/build-ubuntu.sh` |

デスクトップのブランドアイコンを変更するときは、正本の `packages/icons/assets/brand.png`（512×512 px）を更新し、次を実行します。

```sh
npm run launcher:desktop -w packages/icons
```

このコマンドは Windows・Ubuntu・macOS 用の画像を生成します。変更した元画像と生成画像の差分を確認してから、[署名付き Linux パッケージ](dist/linux/sign.md)を再ビルドします。

## トラブルシュート

| 症状 | 確認・対処 |
| --- | --- |
| `fnm` が見つからない・Node.js を切り替えられない | 使用するシェルの設定に fnm の PATH と `fnm env` があることを確認し、現在のシェルでも実行します。ルートで `fnm use` を実行し、`node --version` を確認します |
| ポート 1420 が使用中 | 重複した開発サーバーを終了します。ポートを変更する場合は `vite.config.ts` の `server.port`、`tauri.conf.json` の `build.devUrl` と `app.security.devCsp` 内の開発用 URL を揃えます |
| ブラウザーでは動くがアプリでは失敗する | `npm run dev:desktop` で再現し、ターミナルの Rust ログ、WebView のエラー、`capabilities/default.json` の権限、Tauri の CSP を確認します |
| WebKitGTK・GTK・GStreamer が見つからない | 環境準備の apt コマンドで開発ライブラリを導入し、`pkg-config --modversion webkit2gtk-4.1 gtk+-3.0 gstreamer-1.0` と `gst-inspect-1.0 appsink` を確認します |
| Rust の生成済みメタデータが破損している | `CARGO_TARGET_DIR=/tmp/prelis-linux-debug npm run build:desktop:debug` で別の出力先にビルドし、キャッシュが原因か切り分けます。配布スクリプトを実行するときは既定の出力先に戻します |
| core の変更が反映されない | `packages/core/package.json` の `exports` で `browser` が `./src/index.ts` を指していることと、起動した workspace が `apps/desktop` であることを確認します |

配布物・署名・AppImage の問題は [Linux 配布物のトラブルシュート](dist/linux/sign.md#トラブルシュート)を参照してください。
成果物は `target/` 配下で Git の管理対象外です。コミットしないでください。
