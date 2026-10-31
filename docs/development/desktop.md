# デスクトップ開発

コマンドは、特記がない限り開発・ビルドする OS 上のリポジトリのルートで実行します。後述の手順で同期した場合、Windows 側では `$env:USERPROFILE\prelis-remote`、macOS 側では `~/prelis-remote` が実行場所です。環境条件と成果物の例は Ubuntu（amd64）・Windows 11（x64）・macOS（Apple Silicon）向けです。
Windows の PowerShell では、以下の `npm` を `npm.cmd` に読み替えます（例：`npm.cmd run dev:desktop`）。共通セットアップの `npm ci` も同様です。

## ウィンドウの互換性要件

- デスクトップ版の最小ウィンドウサイズは、コンテンツ領域で **800×600 論理ピクセル**とします。OS の表示倍率を適用した物理ピクセル数とは区別します。画面の作業領域には、これに加えてタイトルバー・ウィンドウ枠が収まる必要があります。
- 通常起動時の既定サイズは1280×860です。起動先モニターの作業領域に収まらない場合は、表示倍率・タイトルバー・ウィンドウ枠を考慮し、最小サイズを下限として縮小・配置します。作業領域にはタスクバーなどを含めません。
- 通常ウィンドウのリサイズに応じて、余白・列幅・見出し・タイマーの大きさを調整します。フルスクリーンや最大化を操作の前提にしません。
- 800×600以上で、ホーム・日記・タイマー・パスワード生成を、ページ全体のスクロールなしで操作できるようにします。日記本文と、長いファイル名・エラーを含む終了音設定の内部スクロールは許容します。
- 最小サイズでも、日記のカレンダー・保存、タイマーの開始・リセット・終了音設定、パスワードの生成条件・生成結果・コピーへアクセスできるようにします。

変更時は800×600、1000×600、1280×600、1024×768、既定の1280×860で確認します。高さだけを縮めた場合と、起動中に縮小・拡大した場合も対象です。終了音設定の展開、タイマーの入力エラー、短いパスワードの警告、文字種の未選択、日記の長文入力・保存失敗・未保存変更の確認ダイアログを含めます。ネイティブアプリでは最小サイズ制限と、小さいモニター・表示倍率変更時の初期配置も確認します。

## 環境準備

Node.js・npm の準備と依存管理は [共通セットアップ](architecture.md#共通セットアップ)を参照してください。デスクトップ固有の条件は次のとおりです。

各 OS とも Rust edition 2024 と依存をビルドできる stable toolchain が必要です。

### Ubuntu

- WebKitGTK 4.1・GTK 3・GStreamer の開発ライブラリと、`gstreamer1.0-plugins-base`・`gstreamer1.0-plugins-good`・`gstreamer1.0-plugins-bad`。音声再生には GStreamer の `appsink` が必要です。
- 配布用ビルドは amd64 を使用します。現在の配布スクリプトは amd64 の成果物名を前提とし、arm64 は未検証です。AppImage も glibc に依存するため、サポートする最も古い Ubuntu をビルド環境の基準にします。

### Windows

- 同期元の Ubuntu に Mutagen と OpenSSH クライアントを用意し、同期先の Windows に鍵認証で SSH 接続できるようにします。
- Microsoft C++ Build Tools の「Desktop development with C++」と、Microsoft Edge WebView2 Runtime を用意します。
- Rust は MSVC toolchain（`stable-x86_64-pc-windows-msvc`）を使用します。`rustup show active-toolchain` で確認できます。
- MSI を作成する場合は Windows のオプション機能「VBSCRIPT」を有効にします。開発起動と `--no-bundle` の debug ビルドには不要です。

インストール方法は [Tauri の Windows 前提条件](https://v2.tauri.app/start/prerequisites/#windows)を参照してください。

Ubuntu 側の `scripts/windows/.env` に SSH 接続先を設定します。ファイルがない場合は [.env.example](../../scripts/windows/.env.example) をコピーして作成します。

同期・配布ビルドは同じ設定を読み込みます。環境変数が `.env` より優先され、`.env` はシェルコードとして実行しません。接続先は `user@host` 形式で指定します。

### macOS

- 同期元の Ubuntu に Mutagen と OpenSSH クライアントを用意し、同期先の Mac でリモートログインを有効にして、鍵認証で SSH 接続できるようにします。
- Mac に Xcode をインストールし、初回起動時のセットアップを完了します。Tauri のデスクトップ開発だけなら Command Line Tools でも構いませんが、現行の macOS ビルドスクリプトは `xcodebuild` を使うため Xcode 本体が必要です。[Tauri の macOS 前提条件](https://v2.tauri.app/start/prerequisites/#macos)も参照してください。
- Mac 上でも Node.js・npm・Rust を準備し、開発に使うターミナルで `node`・`npm`・`cargo` が実行できることを確認します。Rust はホストの CPU に合う stable toolchain を使います。

macOS への同期では `.nvmrc` を除外するため、Node.js のバージョンは Ubuntu 側の `.nvmrc` と[共通セットアップ](architecture.md#共通セットアップ)を確認して Mac に設定します。ビルドスクリプトは `/opt/homebrew/bin` を PATH に追加し、`node` が見つからない場合は fnm の `default` を使います。fnm を使う場合は、その既定バージョンも揃えます。

## 開発起動と動作確認用ビルド

### Ubuntu で開発起動する

```sh
npm run dev:desktop
```

Tauri CLI が Vite と Rust アプリを起動します。

### Windows で開発起動する

まず Ubuntu 側のリポジトリルートで同期スクリプトを実行します。

```sh
./scripts/windows/create-windows-sync.sh
```

Mutagen セッション `prelis-windows` を作成または再利用し、Windows のユーザーディレクトリ直下の `prelis-remote` に同期します。スクリプトが同期完了を確認して正常終了してから、次に進みます。
Ubuntu 側の Mutagen データは `.mutagen-windows/` に保存します。旧 `.mutagen/` に同じ同期元・想定内の同期先パスを持つ `prelis-windows` がある場合は、そのセッションを終了して新しいデータディレクトリで作成します。SSH 接続先や除外設定が変わった既存セッションも作り直します。同期元や同期先パスが想定外の場合は停止します。

初回接続と同期完了待ちは、それぞれ最大300秒です。SSH の接続タイムアウトは10秒とし、Mutagen の作成・同期完了待ちの制限には Ubuntu の `timeout`（coreutils）を使います。省略分を含む競合と一時停止を検出した場合は即時停止し、一時停止中のセッションは移行・再作成しません。競合を解消する際は、同期先の変更を退避してから Ubuntu 側と内容を揃えます。

Windows 実機を直接操作するか、RustDesk で Windows のリモートデスクトップを操作します。同期先のユーザー（現行設定では `builduser`）のデスクトップ上で PowerShell を開き、同期先フォルダに移動して起動します。

```powershell
cd "$env:USERPROFILE\prelis-remote"
npm.cmd ci
npm.cmd run dev:desktop
```

`npm.cmd ci` は初回と依存変更時に、開発サーバーを停止した状態で実行します。Tauri CLI が Windows 上で Vite と Rust アプリを起動します。
同期は Ubuntu から Windows への `one-way-safe` です。ソースは Ubuntu 側で編集し、`node_modules` と Rust の `target` は同期せず Windows 側で生成します。
同期対象はデスクトップ・共有パッケージ・Windows 側のビルド／署名スクリプトです。モバイル・Web・LP・ドキュメント・インフラ・他 OS のスクリプト・各 OS の Mutagen データ・認証情報・生成物は除外します。`.nvmrc` とルートの `package.json`・`package-lock.json` は同期します。
除外設定を変更しても、以前に Windows 側へ同期した不要なファイルは自動削除されません。必要に応じて同期先に残ったファイルを確認・整理してください。

### macOS で開発起動する

まず Ubuntu 側のリポジトリルートで同期スクリプトを実行します。

```sh
./scripts/macos/create-macos-sync.sh
```

Mutagen セッション `prelis-macos` を作成または再利用し、Ubuntu から Mac へ `one-way-safe` で同期します。除外設定が変わった場合は、同期先のファイルを保持してセッションを作り直します。スクリプトが同期完了・接続状態・競合なし・必要ファイルの存在・不要ディレクトリの不在を確認して正常終了してから、次に進みます。Mutagen データは、Windows 用の SSH ラッパーの影響を避けるため `.mutagen-macos/` に分け、`MUTAGEN_SSH_PATH` は解除します。待機時間の制限には Ubuntu の `timeout`（coreutils）を使います。

初回接続と同期完了待ちは、それぞれ最大120秒です。表示件数から省略されたものを含む競合や一時停止を検出した場合は、待ち続けず停止します。`one-way-safe` は Mac 側の異なる内容を上書きしないため、以前のソースが残った同期先でセッションを作り直すと競合することがあります。Mac 側の変更を同期先の外へ退避し、Ubuntu 側を正として該当ファイルの内容を揃えてから再実行します。`node_modules` や Rust の `target` を含む同期先全体の削除は不要です。

Mac のデスクトップ上でターミナルを開き、同期先で起動します。`xcode-select` が Command Line Tools を指している環境でも Xcode 本体を使うため、次の例では `DEVELOPER_DIR` を指定しています。

```sh
cd ~/prelis-remote
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
npm ci
npm run dev:desktop
```

`npm ci` は初回と依存変更時に、開発サーバーを停止した状態で実行します。Tauri CLI が Mac 上で Vite と Rust アプリを起動します。画面の操作は Mac 実機または画面共有で行います。

ソースは Ubuntu 側で編集します。同期対象はルートの `package.json`・`package-lock.json`、デスクトップ・共有パッケージ・Mac 側のビルドスクリプトです。モバイル・Web・LP・ドキュメント・インフラ・他 OS のスクリプト・アイコン生成スクリプト・Git 管理情報・各 OS の Mutagen データ・認証情報・生成物は除外します。`node_modules` と Rust の `target` は Mac 側で生成して再利用します。
除外設定を変更しても、以前に Mac 側へ同期した不要なファイルは自動削除されません。不要ディレクトリが残ってスクリプトが停止した場合は、同期先の内容を確認・整理して再実行します。

### フロントエンドだけを確認する

フロントエンドだけをブラウザーで確認する場合は、次を実行して `http://localhost:1420/` を開きます。

```sh
npm run dev -w apps/desktop
```

ファイル操作など Tauri のネイティブ API を使う機能は、アプリで確認します。

### 動作確認用ビルド

| コマンド | 内容 | 既定の出力先 |
| --- | --- | --- |
| `npm run build -w apps/desktop` | TypeScript の型チェックと Vite ビルド | `apps/desktop/dist/` |
| `npm run build:desktop:debug` | 配布パッケージを作らず debug 実行ファイルを生成 | `apps/desktop/src-tauri/target/debug/desktop` |
| `npm run build:desktop` | release 実行ファイルと配布パッケージを生成 | 実行ファイルは `apps/desktop/src-tauri/target/release/PrelisDesktop`、パッケージは同じ階層の `bundle/` |

上表の Rust 実行ファイル名は Ubuntu 向けです。Windows では debug が `apps/desktop/src-tauri/target/debug/desktop.exe`、release が `apps/desktop/src-tauri/target/release/desktop.exe` になります。
Windows の配布パッケージは `apps/desktop/src-tauri/target/release/bundle/nsis/*-setup.exe` と `apps/desktop/src-tauri/target/release/bundle/msi/*.msi` です。現行設定では WebView2 オフラインインストーラーを同梱するため、ビルド時にそのダウンロードが必要です。
macOS では debug が `apps/desktop/src-tauri/target/debug/desktop`、release が `apps/desktop/src-tauri/target/release/desktop` です。アプリバンドルは `apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app`、DMG は同じ `bundle/` 内の `dmg/` に生成します。通常のビルドはホストの CPU 向けで、Universal ビルドにはなりません。
`CARGO_TARGET_DIR` や Cargo の `build.target-dir` を指定すると Rust 側の出力先が変わります。配布スクリプトは既定の `apps/desktop/src-tauri/target/` を前提にしています。

`npm run build:desktop` は分離署名の作成・検証を行いません。頒布用の deb・AppImage は [Linux 配布物のビルド・署名手順](dist/linux/sign.md)に従います。
Windows も、現行の共通設定だけでビルドした場合はコード署名を行いません。署名付きの NSIS・MSI は [Windows の署名付きビルド](dist/windows/sign.md) のタスクスケジューラ経由の手順で作成・検証し、最終成果物を `dist/windows/v<version>/` に集約します。この手順は現在仮実装で、最新の修正を含めた通し実行は実機未検証です。

### macOS の確認用 App・DMG を Ubuntu から作る

SSH 経由では、Tauri の DMG 作成が Finder の外観設定用 AppleScript で応答待ちになることがあります。Ubuntu からの確認用ビルドには次を使います。Ubuntu 側には、同期用のツールに加えて Python 3 と `sha256sum` が必要です。

```sh
./scripts/macos/build-macos.sh
```

同期後に Mac 上で `npm ci` と `tauri build --bundles app` を実行し、同じ `.app` から ZIP と、`Applications` へのリンクを含む DMG を作ります。DMG は Finder を使わず `hdiutil` で生成します。Mac 側で ZIP の整合性と `hdiutil verify` を確認し、Ubuntu へ回収したファイルの SHA-256 を照合します。

| 成果物 | Ubuntu 側の回収先 |
| --- | --- |
| アプリの ZIP | `apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop_<version>_<arch>.app.zip` |
| DMG | `apps/desktop/src-tauri/target/release/bundle/dmg/PrelisDesktop_<version>_<arch>.dmg` |
| SHA-256 一覧 | `apps/desktop/src-tauri/target/release/bundle/macos-artifacts.sha256` |

`<version>` は共通の `tauri.conf.json` の値、`<arch>` は Apple Silicon で `aarch64`、Intel Mac で `x64` です。Mac 側には `.app` と上記の ZIP・DMG・SHA-256 一覧が残ります。同期済みの Mac で直接同じビルドを行う場合は、`~/prelis-remote` で `bash scripts/macos/build-on-mac.sh` を実行します。

この確認用ビルドは Developer ID 署名・公証を行いません。共通の `npm run build:desktop` も、現行設定では配布用の署名・公証を設定していません。配布時は [macOS 配布物のビルド・署名・公証](dist/macos/sign.md)、または [Mac App Store での頒布](dist/macos/app-store.md)に従います。

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
macOS のビルドスクリプトは共通の `tauri.conf.json` の値を成果物名に使います。配布先別設定にはバージョンを持たせず、共通設定から引き継ぎます。

## 検証

[共通チェック](architecture.md#共通セットアップ)は全 workspace がある Ubuntu 側で実行します。各 OS でデスクトップのフロントエンドをビルドし、変更箇所を Tauri アプリで確認します。Windows・macOS では同期先で実行します。Linux 配布時の署名検証・インストール確認は [Linux 配布物のビルド・署名手順](dist/linux/sign.md#2-成果物と署名を確認する)を参照してください。

Windows では `npm.cmd run build:desktop:debug` で生成した `desktop.exe` も起動し、変更箇所に加えて保存内容の再読込とタイマー完了時の音声を確認します。
NSIS・MSI を作成した場合は両方のインストーラーでインストール・起動・アンインストールと、インストーラー・アプリのアイコンを確認します。MSI はユーザー単位の構成なので、管理者権限のないアカウントでも確認します。

macOS では `npm run build:desktop:debug` で生成した `apps/desktop/src-tauri/target/debug/desktop` を Mac のターミナルから起動し、変更箇所・保存内容の再読込・タイマー完了時の音声を確認します。release の `.app` を作成した場合は、Mac 上で次のように起動します。

```sh
open apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app
```

DMG を作成した場合は、マウントしてアプリと `Applications` リンク、アプリアイコンを確認し、アプリをコピーした後の起動・機能操作も確認します。ZIP・DMG の整合性と SHA-256 の一致だけでは、画面操作や Gatekeeper の通過を確認したことにはなりません。

## 設定の所在とアイコン更新

| 内容 | ファイル |
| --- | --- |
| アプリ名・識別子・ウィンドウ・ビルドフック・フロントエンド出力先 | `apps/desktop/src-tauri/tauri.conf.json` |
| Linux の実行ファイル名・ランチャー用アイコン名 | `apps/desktop/src-tauri/tauri.linux.conf.json` |
| Windows の WebView2 同梱方式・WiX テンプレート・NSIS のインストーラー／アンインストーラー用アイコン | `apps/desktop/src-tauri/tauri.conf.json` の `bundle.windows` |
| Windows MSI のユーザー単位インストール | `apps/desktop/src-tauri/wix/per-user.wxs` |
| macOS の配布先別設定 | `apps/desktop/src-tauri/tauri.appstore.conf.json`・`tauri.github.conf.json` |
| macOS の Mac App Store 用権限 | `apps/desktop/src-tauri/Entitlements.appstore.plist` |
| ネイティブ API の権限とファイルアクセス範囲 | `apps/desktop/src-tauri/capabilities/default.json` |
| Rust の依存・release 最適化 | `apps/desktop/src-tauri/Cargo.toml`・`Cargo.lock` |
| 開発サーバー・ポート・HMR | `apps/desktop/vite.config.ts` |

Ubuntu 版は `tauri.conf.json` に `tauri.linux.conf.json` をマージし、バージョンは共通設定から引き継ぎます。アイコンの更新・生成は [共有アイコン](../../packages/icons/README.md)を参照してください。
Windows 版の設定は `tauri.conf.json` にあり、バージョンも共通設定の値を使用します。アプリと NSIS のインストーラー／アンインストーラーには、共有アイコンから生成する `apps/desktop/src-tauri/icons/icon.ico` を使います。
macOS の通常の開発・確認用ビルドも共通の `tauri.conf.json` を使い、アプリアイコンには共有アイコンから生成する `apps/desktop/src-tauri/icons/icon.icns` を使います。配布時は共通設定に `tauri.appstore.conf.json` または `tauri.github.conf.json` を重ねます。App Store 用の Bundle ID・Sandbox 権限・最低対応 macOS `12.0` は App Store 用設定に限定され、通常の開発設定には適用されません。
