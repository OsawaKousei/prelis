# Windows 11 向けデスクトップビルド

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

## 同期と成果物

送信元は Ubuntu のリポジトリ、送信先は `builduser@192.168.1.10:Dev/prelis-remote` です。同期モードは `one-way-safe` です。Git 管理情報、依存やビルドの生成物、`.env`、ローカル設定などは同期しません。Windows 側の `node_modules` と `target` は Windows で生成して再利用します。

Windows 側の出力は `Dev/prelis-remote/windows-artifacts/`、Ubuntu 側の出力はルートの `windows-artifacts/` です。NSIS インストーラーは `PrelisDesktop_<version>_x64-setup.exe`、実行ファイルは `desktop.exe` です。インストーラーの形式は [Tauri の Windows Installer](https://v2.tauri.app/distribute/windows-installer/) を参照してください。

同期状態の確認には次を使います。

```sh
MUTAGEN_DATA_DIRECTORY="$PWD/.mutagen" mutagen sync list prelis-windows --long
```

`one-way-safe` の競合や同期エラーが出た場合は `mutagen sync list` の内容を確認してから Windows 側の該当ファイルを整理します。スクリプトは同期失敗時にビルドへ進みません。

Windows 実機でインストーラーを実行し、起動と主要機能を確認してください。現時点ではコード署名を設定していません。
