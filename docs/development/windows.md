# Windows 11 向けデスクトップビルド

Mutagen の同期セッションだけを作成・確認する場合は、Ubuntu のリポジトリルートから次を実行します。

```sh
./scripts/create-windows-sync.sh
```

スクリプトは Windows 側の同期先ディレクトリを準備し、同名のセッションが存在する場合は再利用します。同期元・同期先が想定と異なる場合はエラーになります。同期完了まで待機した後、詳細なセッション状態と Windows 側の `package.json` を表示します。

Ubuntu のリポジトリルートから次のコマンドを実行します。

```sh
./scripts/build-windows.sh
```

初回は Mutagen セッション `prelis-windows` を作成し、以降は同じセッションを再利用します。スクリプトは同期完了を待ってから Windows 11 上で `npm ci` と Tauri の NSIS ビルドを実行し、インストーラー、実行ファイル、SHA-256 一覧を Ubuntu の `windows-artifacts/` に回収します。成果物と Mutagen のローカルデータは Git 管理対象外です。

## 前提条件

- Ubuntu に Mutagen、OpenSSH クライアント（`ssh` と `scp`）があること。
- Ubuntu から `builduser@192.168.1.10` に鍵認証で SSH 接続できること。
- Windows 側に Node.js と npm、Rust stable（MSVC target）、Microsoft C++ Build Tools の「Desktop development with C++」、WebView2 Runtime があること。[Tauri の Windows 前提条件](https://v2.tauri.app/start/prerequisites/)を参照してください。
- Windows 側のホームディレクトリに `Dev/prelis-remote` を作成でき、npm と Cargo が必要な依存を取得できること。

Windows の PowerShell では `npm.ps1` が実行ポリシーで止まる場合があるため、[ビルドスクリプト](../../scripts/build-windows.ps1)は `npm.cmd` を使います。Windows SSH の既定シェルが日本語の CP932 でエラーを返す環境では、[Mutagen 用 SSH ラッパー](../../scripts/mutagen-ssh/ssh)がエージェント検出時に Mutagen が認識できる英語エラーを返します。このラッパーはこのリポジトリ専用の Mutagen デーモンにだけ適用されます。

## Windows SSH で Tauri CLI を直接実行する場合

この環境の Windows SSH セッションでは、`npm ci` が作る `node_modules/@prelis/core` と `node_modules/@prelis/icons` の junction を辿れず、型チェックで `TS2307` が発生します。`npm ci` の後にこの2つのリンクを実ディレクトリへ置き換えてから、Tauri CLI を実行します。`rmdir` はリンクだけを削除し、`packages/` の元ファイルは削除しません。

```cmd
cd C:\Users\builduser\Dev\prelis-remote
npm.cmd ci
rmdir node_modules\@prelis\core
rmdir node_modules\@prelis\icons
xcopy packages\core node_modules\@prelis\core /E /I /H /Y
xcopy packages\icons node_modules\@prelis\icons /E /I /H /Y
cd apps\desktop
npx.cmd --no-install tauri build --bundles nsis
```

`npm ci` を再実行すると workspace リンクが再作成されるため、コピーも再実行します。Linux 側から `./scripts/build-windows.sh` を使う場合は、Windows 側のビルドスクリプトがリンクの置き換えを行います。

## 同期と成果物

送信元は Ubuntu のリポジトリ、送信先は `builduser@192.168.1.10:Dev/prelis-remote`（`C:\Users\builduser\Dev\prelis-remote`）です。同期モードは `one-way-safe` です。Git 管理情報、依存やビルドの生成物、`.env`、ローカル設定などは同期しません。Windows 側の `node_modules` と `target` は Windows で生成して再利用します。

Windows 側の出力は `Dev/prelis-remote/windows-artifacts/`、Ubuntu 側の出力はルートの `windows-artifacts/` です。NSIS インストーラーは `PrelisDesktop_<version>_x64-setup.exe`、実行ファイルは `desktop.exe` です。インストーラーの形式は [Tauri の Windows Installer](https://v2.tauri.app/distribute/windows-installer/) を参照してください。

Windows 向けの頒布には NSIS インストーラーの `*-setup.exe` だけを渡せます。`desktop.exe` はビルド確認用の成果物で、頒布する必要はありません。`SHA256SUMS` は利用者へハッシュ値を伝える場合に添付します。Ubuntu 向けには Windows のインストーラーではなく、[Ubuntu 版リリース手順](release.md)で作成する deb または AppImage を頒布します。

同期状態の確認には次を使います。

```sh
MUTAGEN_DATA_DIRECTORY="$PWD/.mutagen" mutagen sync list prelis-windows --long
```

`one-way-safe` の競合や同期エラーが出た場合は `mutagen sync list` の内容を確認してから Windows 側の該当ファイルを整理します。スクリプトは同期失敗時にビルドへ進みません。

Windows 実機でインストーラーを実行し、起動と主要機能、インストーラーとアプリのアイコンを確認してください。NSIS インストーラーとアンインストーラーのアイコンは `tauri.conf.json` の `bundle.windows.nsis` で指定しています。現時点ではコード署名を設定していません。
