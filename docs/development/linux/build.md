# Linux 向け deb・AppImage のビルド

Ubuntu（amd64）での環境準備、デスクトップアプリの開発起動、deb・AppImage のビルドと署名、動作確認、直接頒布までをまとめます。
コマンドは、特記がない限り取得済みのリポジトリのルートで実行します。GUI の動作確認には Ubuntu のデスクトップセッションが必要です。
依存パッケージ、Node.js、Rust、AppImage 作成ツールの取得にはネットワーク接続を使います。

## Linux 版の配布構成

| 配布形式 | 利用方法 | 更新方法 |
| --- | --- | --- |
| deb | `.deb` を直接インストールする | 新しい `.deb` を取得してインストールする |
| AppImage | ファイルに実行権限を付けて起動する | 新しい AppImage に差し替える |
| APT リポジトリ | `stable` / `main` から `prelis-desktop` をインストールする | APT で更新する |
| Snap Store | `prelis` をインストールする | Snap Store のチャンネルに従って更新する |

ビルドを担当するのは `scripts/linux/build-ubuntu.sh` です。
作成した deb は直接頒布するほか、同じファイルを APT リポジトリに登録したり、Snap の作成元に使ったりできます。AppImage は直接頒布します。
この文書は deb・AppImage の作成と直接頒布までを扱います。APT リポジトリへの登録・公開と Snap の作成・Store 公開は、別途整理する範囲です。

## 環境準備

共通の依存管理と初回セットアップは [architecture.md](../architecture.md#共通セットアップ)を参照してください。
ローカルマシンの OS・ツールのバージョン・導入先・導入済みの基本 APT パッケージは [local-linux.md](../../environment/local-linux.md)にまとめています。

### Ubuntu とネイティブ依存

配布先と同じ amd64 の Ubuntu を使用します。現在のスクリプトは amd64 の成果物名を前提とし、arm64 は未検証です。
AppImage も glibc などの制約を受けるため、サポートする最も古い Ubuntu をビルド環境の基準にします。新しい Ubuntu で作った成果物が古い Ubuntu で動くとは限りません。

```sh
dpkg --print-architecture
```

出力が `amd64` であることを確認します。
新しい環境では、まず [local-linux.md の基本 APT パッケージ](../../environment/local-linux.md)を導入してください。
それに加え、以下の補助ツール、GTK 3、署名・検証用ツール、音声用の GStreamer を用意します。ローカル環境メモの導入済み一覧だけでは、配布ビルドに必要な依存がすべて揃っているとは限りません。

```sh
sudo apt update
sudo apt install \
  pkg-config unzip ca-certificates libgtk-3-dev \
  libgstreamer1.0-dev gstreamer1.0-tools \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  gnupg dpkg coreutils

pkg-config --modversion webkit2gtk-4.1 gtk+-3.0 gstreamer-1.0
gst-inspect-1.0 appsink
```

AppImage に同梱するプラグインは、後述するタイマーの音声再生でも確認します。

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

fnm を使える状態にしたら、[共通の初回セットアップ](../architecture.md#初回セットアップ)に従い、Node.js の選択、npm 依存のインストール、共通チェックを実行します。
Node.js・npm の要件と workspaces・lockfile の管理方法は [architecture.md の依存管理](../architecture.md#依存管理)を参照してください。

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

### 署名鍵と出力先

署名付き配布パッケージの作成には GPG 秘密鍵が必要です。
鍵の識別情報、ホスト OS 上の所在・権限、登録確認コマンドは [Linux 配布用の署名鍵](../../environment/signing-key.md)にまとめています。
同文書の確認コマンドで `RELEASE_KEY_FPR` を設定し、秘密鍵が利用できることを確認してください。
開発起動と署名を伴わない debug ビルドにはこの鍵は不要です。

現在の配布スクリプトは `apps/desktop/src-tauri/target/` から成果物を探します。出力先を揃えるため、別の出力先を指定している場合は解除します。

```sh
unset CARGO_TARGET_DIR
```

Cargo のユーザー設定やプロジェクト設定で `build.target-dir` を指定している場合も、配布スクリプトを使う際は既定の出力先に戻してください。

## 開発起動と動作確認用ビルド

```sh
npm run dev:desktop
```

Tauri CLI が Vite と Rust アプリを起動します。終了する場合はターミナルで `Ctrl+C` を押します。
共有ロジック `@prelis/core` のソース解決とビルドが必要になる条件は、[architecture.md](../architecture.md) の「依存管理」「依存の追加・更新」を参照してください。

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
`npm run build:desktop` は汎用の Tauri ビルドで、後述する分離署名の作成・検証処理は実行しません。直接頒布する deb・AppImage は `scripts/linux/build-ubuntu.sh` で作成します。
debug の成功に加え、配布パッケージごとの署名検証とインストール後の動作確認が必要です。

## 1. バージョンを揃える

リリースするバージョンを、次の 3 か所で同じ値に揃えます。

| ファイル | 項目 |
| --- | --- |
| `apps/desktop/src-tauri/tauri.conf.json` | `version` |
| `apps/desktop/src-tauri/Cargo.toml` | `package.version` |
| `apps/desktop/package.json` | `version` |

`Cargo.toml` を更新したら `apps/desktop/src-tauri/Cargo.lock` の更新も差分に含めます。
スクリプトはデスクトップの `package.json` の値を成果物名の確認に使います。

## 2. ビルド前に検証する

```sh
npm run check
npm run build -w apps/desktop
```

`npm run check` の確認範囲は [共通セットアップ](../architecture.md#共通セットアップ)を参照してください。
フロントエンドの確認、配布パッケージの作成、インストール後の動作確認を順に行います。

## 3. パッケージを作成する

```sh
./scripts/linux/build-ubuntu.sh
```

スクリプトは指定された秘密鍵を確認し、Tauri CLI で deb と AppImage をビルドします。
Tauri の `beforeBuildCommand` によりフロントエンドもビルドされます。初回は Rust の依存コンパイルに時間がかかります。

AppImage には `LDAI_SIGN=1` と `LDAI_SIGN_KEY` で GPG 埋め込み署名を付けます。
生成後、`--appimage-signature` の出力に署名が存在することを確認します。この確認は埋め込み署名の暗号学的な検証ではありません。
さらに deb と AppImage の両方に分離署名（`.asc`）を付け、`gpg --verify` で検証します。
別の鍵を使う場合は `RELEASE_KEY_FPR=<40桁のフィンガープリント> ./scripts/linux/build-ubuntu.sh` と指定します。

| 成果物 | 出力先 |
| --- | --- |
| deb | `apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_<version>_amd64.deb` |
| deb の分離署名 | `apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_<version>_amd64.deb.asc` |
| AppImage | `apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_<version>_amd64.AppImage` |
| AppImage の分離署名 | `apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_<version>_amd64.AppImage.asc` |

パッケージのメタデータと Linux 固有の設定は次のとおりです。

| 内容 | 設定元・確認方法 |
| --- | --- |
| 発行元・カテゴリ・説明・deb セクション | `apps/desktop/src-tauri/tauri.conf.json` の `bundle` |
| Maintainer | `Cargo.toml` の `package.authors` |
| 製品名・deb パッケージ名 | `tauri.conf.json` の `productName`。deb の `Package` は `dpkg-deb -f` で確認（現行成果物は `prelis-desktop`） |
| Linux の実行ファイル名 | `apps/desktop/src-tauri/tauri.linux.conf.json` の `mainBinaryName`（`PrelisDesktop`） |
| 依存パッケージ | Tauri が生成する deb の `Depends` で確認（既存の 0.1.1 は `libwebkit2gtk-4.1-0`、`libgtk-3-0`） |
| アプリアイコン | `packages/icons/assets/brand.png` から生成する `apps/desktop/src-tauri/icons/` の画像 |

## 4. 成果物と署名を確認する

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_${version}_amd64.deb"
appimage="apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_${version}_amd64.AppImage"
dpkg-deb -f "$deb" Package Version Architecture Maintainer Section Depends
dpkg-deb -I "$deb"
dpkg-deb -c "$deb"
gpg --verify "${deb}.asc" "$deb"
gpg --verify "${appimage}.asc" "$appimage"
sha256sum "$deb" "${deb}.asc" "$appimage" "${appimage}.asc"
```

`Package: prelis-desktop`、意図した `Version`、`Architecture: amd64` と、対象 Ubuntu で解決可能な `Depends` を確認します。
署名は検証成功に加えて、署名鍵のフィンガープリントが意図した値と一致することを確認します。

## 5. Ubuntu でインストール・起動を確認する

可能ならクリーンな Ubuntu amd64 環境に成果物を渡して確認します。
以下はビルド環境で実行する場合の例です。別の環境では `deb`・`appimage` に作業ディレクトリからのコピー先の相対パスを設定してください。

```sh
# deb（前節の変数を使用）
sudo apt install "./${deb}"
PrelisDesktop

# AppImage
chmod +x "$appimage"
"./${appimage}"
```

- アプリが起動し、Diary・Timer・Password の主要操作ができること。保存した内容の再読込とタイマー完了時の音声も確認します。
- アプリランチャーから起動でき、ランチャーと起動中のウィンドウに共通アイコンが表示されること。Linux の実行ファイル名、アイコン名、`StartupWMClass` は `PrelisDesktop` に揃えています。
- deb は `sudo apt remove prelis-desktop` で削除できること。
- 更新版では旧版からの更新後も起動・保存データの利用ができること。

ファイルマネージャー上の deb ファイルは通常、パッケージ形式の汎用アイコンになります。
AppImage ファイルのアイコン表示とランチャーへの登録には、ファイルマネージャーの対応や AppImage のデスクトップ統合が必要です。

AppImage が FUSE 不足で起動できない場合、Ubuntu 22.04 では `sudo apt install libfuse2`、Ubuntu 24.04 では `sudo apt install libfuse2t64` を使用します。
FUSE を使えない環境では `"./${appimage}" --appimage-extract-and-run` で展開して起動できます。

## 6. 直接頒布する

ビルドと動作確認が完了した成果物を公開します。

1. 変更をコミットし、`v<version>` のタグを付けて push します。
2. GitHub Releases などに deb、対応する `.deb.asc`、AppImage、対応する `.AppImage.asc`、`sha256sum` の結果を添付します。
3. リリースノートに確認した Ubuntu のバージョン・amd64、インストール手順、既知の問題を記載します。

公開するファイルは、動作確認したファイルと同じものを使います。同じバージョン番号で内容だけ変えて再頒布せず、修正時はバージョンを上げて作り直します。

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

このコマンドは Windows・Ubuntu・macOS 用の画像を生成します。変更した元画像と生成画像の差分を確認してから、Linux パッケージを再ビルドします。

## トラブルシュート

| 症状 | 確認・対処 |
| --- | --- |
| `fnm` が見つからない・Node.js を切り替えられない | 使用するシェルの設定に fnm の PATH と `fnm env` があることを確認し、現在のシェルでも実行します。ルートで `fnm use` を実行し、`node --version` を確認します |
| ポート 1420 が使用中 | 重複した開発サーバーを終了します。ポートを変更する場合は `vite.config.ts` の `server.port`、`tauri.conf.json` の `build.devUrl` と `app.security.devCsp` 内の開発用 URL を揃えます |
| ブラウザーでは動くがアプリでは失敗する | `npm run dev:desktop` で再現し、ターミナルの Rust ログ、WebView のエラー、`capabilities/default.json` の権限、Tauri の CSP を確認します |
| WebKitGTK・GTK・GStreamer が見つからない | 環境準備の apt コマンドで開発ライブラリを導入し、`pkg-config --modversion webkit2gtk-4.1 gtk+-3.0 gstreamer-1.0` と `gst-inspect-1.0 appsink` を確認します |
| Rust の生成済みメタデータが破損している | `CARGO_TARGET_DIR=/tmp/prelis-linux-debug npm run build:desktop:debug` で別の出力先にビルドし、キャッシュが原因か切り分けます。配布スクリプトを実行するときは既定の出力先に戻します |
| core の変更が反映されない | `packages/core/package.json` の `exports` で `browser` が `./src/index.ts` を指していることと、起動した workspace が `apps/desktop` であることを確認します |
| GPG 秘密鍵が見つからない | [署名鍵の情報](../../environment/signing-key.md)に従い、GnuPG ホーム、秘密鍵の登録、フィンガープリントを確認します |
| 署名の入力待ちでビルドが止まる | パスフレーズ入力画面を確認します。端末で署名する場合は `export GPG_TTY="$(tty)"` を設定して再実行します |
| ビルド後に成果物が見つからない | `CARGO_TARGET_DIR`・Cargo の `build.target-dir`、3 か所のバージョン、amd64 環境であることを確認します |
| AppImage が FUSE エラーで起動しない | Ubuntu 22.04 は `libfuse2`、24.04 は `libfuse2t64` を導入するか、`--appimage-extract-and-run` を付けて起動します |
| AppImage で音声が鳴らない・WebView が停止する | `bundle.linux.appimage.bundleMediaFramework` が `true` であることと、ビルド環境に必要な GStreamer プラグインがあることを確認し、作り直します |

## 注意

- AppImage は `tauri.conf.json` の `bundle.linux.appimage.bundleMediaFramework: true` で GStreamer を同梱します。無効にすると `GStreamer element appsink not found` などの不具合が発生する場合があります。この同梱機能は Ubuntu のビルド環境を前提とし、実行時に必要なプラグインをビルド環境へ用意します。
- `.deb.asc` は deb ファイルを検証するための分離署名です。`apt install ./...deb` はこの署名を自動検証しません。APT リポジトリでは別の鍵で `InRelease` または `Release.gpg` に署名します。Snap Store の署名も直接頒布用の GPG 署名とは別です。
- 成果物は `target/` 配下で Git の管理対象外です。コミットしないでください。
