# デスクトップ開発

コマンドは、特記がない限り開発・ビルドする OS 上のリポジトリのルートで実行します。Windows 側では、後述の手順で同期した `$env:USERPROFILE\prelis-remote` が実行場所です。環境条件と成果物の例は Ubuntu（amd64）と Windows 11（x64）向けです。
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

両 OS とも Rust edition 2024 と依存をビルドできる stable toolchain が必要です。

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

```dotenv
PRELIS_WINDOWS_SSH_HOST=builduser@192.168.10.20
```

同期・配布ビルドは同じ設定を読み込みます。環境変数が `.env` より優先され、`.env` はシェルコードとして実行しません。接続先は `user@host` 形式で指定します。

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
`CARGO_TARGET_DIR` や Cargo の `build.target-dir` を指定すると Rust 側の出力先が変わります。配布スクリプトは既定の `apps/desktop/src-tauri/target/` を前提にしています。

`npm run build:desktop` は分離署名の作成・検証を行いません。頒布用の deb・AppImage は [Linux 配布物のビルド・署名手順](dist/linux/sign.md)に従います。
Windows も、現行の共通設定だけでビルドした場合はコード署名を行いません。署名付きの NSIS・MSI は [Windows の署名付きビルド](dist/windows/sign.md) のタスクスケジューラ経由の手順で作成・検証し、最終成果物を `dist/windows/v<version>/` に集約します。この手順は現在仮実装で、最新の修正を含めた通し実行は実機未検証です。

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

[共通チェック](architecture.md#共通セットアップ)は全 workspace がある Ubuntu 側で実行します。各 OS でデスクトップのフロントエンドをビルドし、変更箇所を Tauri アプリで確認します。Windows では同期先で実行します。配布時の署名検証・インストール確認は [Linux 配布物のビルド・署名手順](dist/linux/sign.md#2-成果物と署名を確認する)を参照してください。

Windows では `npm.cmd run build:desktop:debug` で生成した `desktop.exe` も起動し、変更箇所に加えて保存内容の再読込とタイマー完了時の音声を確認します。
NSIS・MSI を作成した場合は両方のインストーラーでインストール・起動・アンインストールと、インストーラー・アプリのアイコンを確認します。MSI はユーザー単位の構成なので、管理者権限のないアカウントでも確認します。

## 設定の所在とアイコン更新

| 内容 | ファイル |
| --- | --- |
| アプリ名・識別子・ウィンドウ・ビルドフック・フロントエンド出力先 | `apps/desktop/src-tauri/tauri.conf.json` |
| Linux の実行ファイル名・ランチャー用アイコン名 | `apps/desktop/src-tauri/tauri.linux.conf.json` |
| Windows の WebView2 同梱方式・WiX テンプレート・NSIS のインストーラー／アンインストーラー用アイコン | `apps/desktop/src-tauri/tauri.conf.json` の `bundle.windows` |
| Windows MSI のユーザー単位インストール | `apps/desktop/src-tauri/wix/per-user.wxs` |
| macOS の配布先別設定 | `apps/desktop/src-tauri/tauri.appstore.conf.json`・`tauri.github.conf.json` |
| ネイティブ API の権限とファイルアクセス範囲 | `apps/desktop/src-tauri/capabilities/default.json` |
| Rust の依存・release 最適化 | `apps/desktop/src-tauri/Cargo.toml`・`Cargo.lock` |
| 開発サーバー・ポート・HMR | `apps/desktop/vite.config.ts` |

Ubuntu 版は `tauri.conf.json` に `tauri.linux.conf.json` をマージし、バージョンは共通設定から引き継ぎます。アイコンの更新・生成は [共有アイコン](../../packages/icons/README.md)を参照してください。
Windows 版の設定は `tauri.conf.json` にあり、バージョンも共通設定の値を使用します。アプリと NSIS のインストーラー／アンインストーラーには、共有アイコンから生成する `apps/desktop/src-tauri/icons/icon.ico` を使います。
