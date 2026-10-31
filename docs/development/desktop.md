# デスクトップ開発

コマンドは、特記がない限り開発・ビルドする OS 上のリポジトリのルートで実行します。後述の手順で同期した場合、Windows 側では `$env:USERPROFILE\prelis-remote`、macOS 側では `~/prelis-remote` が実行場所です。環境条件と成果物の例は Ubuntu（amd64）・Windows 11（x64）・macOS（Apple Silicon）向けです。
Windows の PowerShell では、以下の `npm` を `npm.cmd` に読み替えます（例：`npm.cmd run dev:desktop`）。共通セットアップの `npm ci` も同様です。

## ウィンドウの互換性要件

- デスクトップ版の最小ウィンドウサイズは、コンテンツ領域で **800×600 論理ピクセル**とします。OS の表示倍率を適用した物理ピクセル数とは区別します。画面の作業領域には、これに加えてタイトルバー・ウィンドウ枠が収まる必要があります。
- 通常起動時の既定サイズは1280×860です。起動先モニターの作業領域に収まらない場合は、表示倍率・タイトルバー・ウィンドウ枠を考慮し、最小サイズを下限として縮小・配置します。作業領域にはタスクバーなどを含めません。
- 通常ウィンドウのリサイズに応じて、余白・列幅・見出し・タイマーの大きさを調整します。フルスクリーンや最大化を操作の前提にしません。
- 800×600以上で、各種アプリページ全体をスクロールなしで操作できるようにします。テキスト入力欄やエラー表示などの内部スクロールは許容します。

変更時は800×600、1000×600、1280×600、1024×768、既定の1280×860で確認します。高さだけを縮めた場合と、起動中に縮小・拡大した場合も対象です。

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

macOS の同期・ビルドの接続先と作業パスは `scripts/macos/.env` の `PRELIS_MACOS_SSH_HOST`・`PRELIS_MACOS_REMOTE_ROOT` に設定します。[.env.example](../../scripts/macos/.env.example) を初回だけコピーして権限を `0600` にし、使用する環境の値を記入してください。署名に関するキーは配布ビルド時に設定します。

`.nvmrc` も Mac へ同期します。Mac のビルドスクリプトはその Node.js の版を使い、fnm の `default` には依存しません。fnm を使う場合は事前にその版をインストールします。

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
Ubuntu 側の Mutagen データは `.mutagen-windows/` に保存します。SSH 接続先や除外設定が変わった既存セッションも作り直します。同期元や同期先パスが想定外の場合は停止します。

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

`one-way-safe` は Mac 側の異なる内容を上書きしないため、以前のソースが残った同期先でセッションを作り直すと競合することがあります。Mac 側の変更を同期先の外へ退避し、Ubuntu 側を正として該当ファイルの内容を揃えてから再実行します。`node_modules` や Rust の `target` を含む同期先全体の削除は不要です。

Mac のデスクトップ上でターミナルを開き、同期先で起動します。`xcode-select` が Command Line Tools を指している環境でも Xcode 本体を使うため、次の例では `DEVELOPER_DIR` を指定しています。

```sh
cd ~/prelis-remote
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
npm ci
npm run dev:desktop
```

`npm ci` は初回と依存変更時に、開発サーバーを停止した状態で実行します。Tauri CLI が Mac 上で Vite と Rust アプリを起動します。画面の操作は Mac 実機または画面共有で行います。

ソースは Ubuntu 側で編集します。同期対象はルートの `package.json`・`package-lock.json`、デスクトップ・共有パッケージ・Mac 側のビルドスクリプトと `.nvmrc` です。モバイル・Web・LP・ドキュメント・インフラ・他 OS のスクリプト・アイコン生成スクリプト・Git 管理情報・各 OS の Mutagen データ・認証情報・生成物は除外します。`node_modules` と Rust の `target` は Mac 側で生成して再利用します。
除外設定を変更しても、以前に Mac 側へ同期した不要なファイルは自動削除されません。不要ディレクトリが残ってスクリプトが停止した場合は、同期先の内容を確認・整理して再実行します。

### フロントエンドだけを確認する

フロントエンドだけをブラウザーで確認する場合は、次を実行して `http://localhost:1420/` を開きます。

```sh
npm run dev -w apps/desktop
```

ファイル操作など Tauri のネイティブ API を使う機能は、アプリで確認します。

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

## 設定の所在とアイコン更新

| 内容 | ファイル |
| --- | --- |
| アプリ名・識別子・ウィンドウ・ビルドフック・フロントエンド出力先 | `apps/desktop/src-tauri/tauri.conf.json` |
| Linux の実行ファイル名・ランチャー用アイコン名 | `apps/desktop/src-tauri/tauri.linux.conf.json` |
| Windows の WebView2 同梱方式・WiX テンプレート・NSIS のインストーラー／アンインストーラー用アイコン | `apps/desktop/src-tauri/tauri.conf.json` の `bundle.windows` |
| Windows MSI のユーザー単位インストール | `apps/desktop/src-tauri/wix/per-user.wxs` |
| macOS の配布先別設定 | `apps/desktop/src-tauri/tauri.appstore.conf.json`・`tauri.github.conf.json` |
| macOS の Mac App Store 用権限 | `apps/desktop/src-tauri/Entitlements.appstore.plist` を元に `signing/Entitlements.appstore.plist` を生成 |
| ネイティブ API の権限とファイルアクセス範囲 | `apps/desktop/src-tauri/capabilities/default.json` |
| Rust の依存・release 最適化 | `apps/desktop/src-tauri/Cargo.toml`・`Cargo.lock` |
| 開発サーバー・ポート・HMR | `apps/desktop/vite.config.ts` |

Ubuntu 版は `tauri.conf.json` に `tauri.linux.conf.json` をマージし、バージョンは共通設定から引き継ぎます。アイコンの更新・生成は [共有アイコン](../../packages/icons/README.md)を参照してください。
Windows 版の設定は `tauri.conf.json` にあり、バージョンも共通設定の値を使用します。アプリと NSIS のインストーラー／アンインストーラーには、共有アイコンから生成する `apps/desktop/src-tauri/icons/icon.ico` を使います。
macOS の通常の開発・確認用ビルドも共通の `tauri.conf.json` を使い、アプリアイコンには共有アイコンから生成する `apps/desktop/src-tauri/icons/icon.icns` を使います。配布時は共通設定に `tauri.appstore.conf.json` または `tauri.github.conf.json` を重ねます。App Store 用の Bundle ID・Sandbox 権限・最低対応 macOS `12.0` は App Store 用設定に限定され、通常の開発設定には適用されません。
