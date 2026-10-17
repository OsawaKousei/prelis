# Windows 11 向けデスクトップビルド

## 同期

Ubuntu のリポジトリルートで、次を実行します。

```sh
./scripts/windows/create-windows-sync.sh
```

スクリプトは Windows のユーザーディレクトリ直下に `prelis-remote` を作成し、Mutagen セッション `prelis-windows` で同期します。既存のセッションが以前の `Dev/prelis-remote` を指している場合は、新しい同期先へ作り直します。同期完了後、セッション状態と Windows 側の `package.json` を確認します。

## Windows でビルド

VNC で Windows にログインし、PowerShell で次を実行します。

```powershell
cd "$env:USERPROFILE\prelis-remote"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build.ps1
```

スクリプトはリポジトリルートで `npm.cmd ci` を実行し、Tauri の NSIS インストーラーをビルドします。`npm.cmd` を使うのは、PowerShell の実行ポリシーによって `npm.ps1` が止まる環境に対応するためです。

## 前提条件

- Ubuntu に Mutagen と OpenSSH クライアント（`ssh`）があること。
- Ubuntu から `builduser@192.168.1.10` に鍵認証で SSH 接続できること。
- Windows 側に Node.js と npm、Rust stable（MSVC target）、Microsoft C++ Build Tools の「Desktop development with C++」、WebView2 Runtime があること。[Tauri の Windows 前提条件](https://v2.tauri.app/start/prerequisites/)を参照してください。
- Windows 側のユーザーディレクトリ直下に `prelis-remote` を作成でき、npm と Cargo が必要な依存を取得できること。

Windows SSH の既定シェルが日本語の CP932 でエラーを返す環境では、[Mutagen 用 SSH ラッパー](../../scripts/mutagen-ssh/ssh)がエージェント検出時に Mutagen が認識できる英語エラーを返します。このラッパーはこのリポジトリ専用の Mutagen デーモンにだけ適用されます。

## 同期と成果物

送信元は Ubuntu のリポジトリ、送信先は `builduser@192.168.1.10:prelis-remote`（`C:\Users\builduser\prelis-remote`）です。同期モードは `one-way-safe` です。Git 管理情報、依存やビルドの生成物、`.env`、ローカル設定などは同期しません。Windows 側の `node_modules` と `target` は Windows で生成して再利用します。

NSIS インストーラーは Windows 側の `prelis-remote\apps\desktop\src-tauri\target\release\bundle\nsis\PrelisDesktop_<version>_x64-setup.exe`、実行ファイルは `prelis-remote\apps\desktop\src-tauri\target\release\desktop.exe` に生成されます。インストーラーの形式は [Tauri の Windows Installer](https://v2.tauri.app/distribute/windows-installer/) を参照してください。

Windows 向けの頒布には NSIS インストーラーの `*-setup.exe` だけを渡せます。`desktop.exe` はビルド確認用の成果物で、頒布する必要はありません。Ubuntu 向けには Windows のインストーラーではなく、[Ubuntu 版リリース手順](release.md)で作成する deb または AppImage を頒布します。

同期状態の確認には次を使います。

```sh
MUTAGEN_DATA_DIRECTORY="$PWD/.mutagen" mutagen sync list prelis-windows --long
```

`one-way-safe` の競合や同期エラーが出た場合は `mutagen sync list` の内容を確認してから Windows 側の該当ファイルを整理します。Windows 側のビルドは、同期スクリプトが正常終了してから始めてください。

Windows 実機でインストーラーを実行し、起動と主要機能、インストーラーとアプリのアイコンを確認してください。NSIS インストーラーとアンインストーラーのアイコンは `tauri.conf.json` の `bundle.windows.nsis` で指定しています。現時点ではコード署名を設定していません。
