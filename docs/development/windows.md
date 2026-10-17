# Windows 11 向けデスクトップビルド

## 一括手順

Ubuntu のリポジトリルートで、次を実行します。

```sh
./scripts/windows/build-windows.sh
```

スクリプトは VNC 用の SSH トンネルを開始し、Mutagen の同期完了後に署名用の認証情報を Windows のユーザーディレクトリへ一時転送します。Ubuntu 側の端末は開いたまま、VNC クライアントで `127.0.0.1:22118` に接続し、画面に表示された Windows 側のビルドコマンドをそのまま実行してください。ビルドが成功したら Ubuntu 側のターミナルで Enter キーを押します。完了前に Enter を押しても確認待ちを続けます。Windows 側で失敗した場合は Ubuntu 側で Ctrl+C を押して一時認証ファイルを削除し、最初からやり直してください。スクリプトは今回の署名済みビルドの完了を確認し、NSIS と MSI の成果物を `scp` で Ubuntu 側の `apps/desktop/src-tauri/target/release/bundle/` に回収します。SSH トンネルと一時認証ファイルはスクリプト終了時に削除します。前回のトンネルが残っている場合は、次回の起動時に同じ制御ソケットから終了させます。

## Azure Artifact Signing の設定

Ubuntu のリポジトリルートでサンプルを `scripts/windows/.env` にコピーし、6 項目を実際の値に置き換えます。シェルの環境変数として設定しても構いません（環境変数が `.env` より優先されます）。`.env` は Git と Mutagen の同期から除外されます。値に空白や `#` がある場合は引用符で囲めますが、変数展開やエスケープ文字は解釈しません。`$env:...` は Windows PowerShell の構文なので、Ubuntu の `.env` では `KEY=value` 形式を使います。

```sh
cp scripts/windows/.env.example scripts/windows/.env
chmod 600 scripts/windows/.env
```

別のファイルを使う場合は `PRELIS_SIGNING_ENV_FILE=/path/to/file ./scripts/windows/build-windows.sh` と指定できます。エンドポイントはアカウントの Azure リージョンと一致させてください。アプリ登録には対象の証明書プロファイルの **Artifact Signing Certificate Profile Signer** ロールが必要です。Windows には [Artifact Signing Client Tools](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations) をインストールしてください。dlib はユーザー領域の `AppData\Local\Microsoft\MicrosoftArtifactSigningClientTools` と `Program Files` 内のインストール先を検索します。x64 の SignTool または dlib を自動検出できない場合は、Windows 側で `PRELIS_SIGNTOOL_PATH` と `PRELIS_ARTIFACT_SIGNING_DLIB_PATH` に各ファイルの絶対パスを設定します。

認証情報は Ubuntu で実行せずに読み取り、SSH の標準入力で Windows 側の受信用スクリプトへ渡します。受信用スクリプトが Windows ユーザーディレクトリに一時ファイルを作り、その存在を確認してからビルドコマンドを表示します。Windows の `build.ps1` は一時ファイルを読み取り、プロセス環境変数で署名ツールへ渡します。Tauri がインストーラーへ組み込むアプリ本体とインストーラーに署名します。Tauri は各インストーラーの作成後に作業ディレクトリの `desktop.exe` を未署名の元データへ戻すため、スクリプトが最後に単体の `desktop.exe` も署名し、SignTool で３つの成果物を検証します。ビルドの成功・失敗どちらでも Windows 側の認証ファイルと一時設定ファイルを削除し、Ubuntu 側スクリプトも終了時に転送先を削除します。Windows 側のビルドを実行しなかった場合も、Ubuntu 側スクリプトを終了すると転送先を削除します。強制終了や通信断で両方の後片付けが走らなかった場合は、Windows ユーザーディレクトリの `prelis-signing-*.env` を手動で削除してください。

署名時に `AADSTS700016` が出た場合、Azure が指定のテナント内でアプリ登録を見つけられていません。Microsoft Entra ID の「アプリの登録」で対象アプリの概要を開き、`scripts/windows/.env` の `AZURE_TENANT_ID` が「ディレクトリ (テナント) ID」、`AZURE_CLIENT_ID` が「アプリケーション (クライアント) ID」と一致するか確認してください。オブジェクト ID は使いません。アプリが別テナントにある場合は、署名対象の Artifact Signing リソースとアプリの関係も確認します。ID を修正した後は、Ubuntu 側の署名スクリプトを最初から実行して新しい一時認証ファイルを作ります。認証が通った後に権限エラーが出る場合は、サービスプリンシパルに **Artifact Signing Certificate Profile Signer** ロールが付与されているか確認してください。

## 同期のみ実行する場合

```sh
./scripts/windows/create-windows-sync.sh
```

同期スクリプトは Windows のユーザーディレクトリ直下に `prelis-remote` を作成し、Mutagen セッション `prelis-windows` で同期します。既存のセッションが以前の `Dev/prelis-remote` を指している場合は、新しい同期先へ作り直します。Windows 側の接続と初回同期を待ってから `flush` し、同期完了後にセッション状態と Windows 側の `package.json` を確認します。

## Windows 側のビルドコマンド

VNC で Windows にログインし、PowerShell で Ubuntu 側スクリプトが表示したコマンドを実行します。表示コマンドには今回の一時ファイル名と完了確認ファイル名が含まれます。

```powershell
cd "$env:USERPROFILE\prelis-remote"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build.ps1 -CredentialFile "prelis-signing-<表示された名前>.env" -CompletionFile "prelis-build-<表示された名前>.ok"
```

スクリプトはリポジトリルートで `npm.cmd ci` を実行し、Tauri の NSIS・MSI インストーラーをビルドして署名します。`npm.cmd` を使うのは、PowerShell の実行ポリシーによって `npm.ps1` が止まる環境に対応するためです。署名や検証に失敗した場合は完了ファイルを作らず、Ubuntu 側は古い成果物を回収しません。

## ビルド済み成果物の署名のみを試す

Windows 側の `prelis-remote\apps\desktop\src-tauri\target\release\bundle\` に NSIS と MSI の成果物が残っている場合、Ubuntu のリポジトリルートから次を実行できます。

```sh
./scripts/windows/sign-windows.sh
```

一括手順と同じように、表示された Windows 側の PowerShell コマンドを VNC で実行し、署名完了後に Ubuntu 側で Enter キーを押します。この手順では `npm ci` と Tauri ビルドを行いません。Windows 側の既存 NSIS・MSI と、存在する場合は単体の `desktop.exe` を一時コピーで署名・検証し、成功後に元のファイルへ反映して Ubuntu へインストーラーを回収します。署名・検証が終わるまでは元の成果物を変更せず、反映中に失敗した場合はバックアップから復元を試みます。

完成済みインストーラーの内部に格納された `desktop.exe` の署名は、この手順では変わりません。インストール後のアプリ本体まで署名された頒布物を作る場合は、署名を組み込んだ `build-windows.sh` で再ビルドしてください。

## 前提条件

- Ubuntu に Mutagen、OpenSSH クライアント（`ssh` と `scp`）、`flock`、VNC クライアントがあること。
- Ubuntu から `builduser@192.168.1.10` に鍵認証で SSH 接続できること。
- Windows 側の VNC サーバーが `127.0.0.1:21118` で接続を受け付けること。
- Windows 側に Node.js と npm、Rust stable（MSVC target）、Microsoft C++ Build Tools の「Desktop development with C++」、WebView2 Runtime があること。[Tauri の Windows 前提条件](https://v2.tauri.app/start/prerequisites/)を参照してください。
- MSI ビルド用に Windows のオプション機能「VBSCRIPT」が有効であること。`light.exe` の実行に失敗する場合は [Tauri の手順](https://v2.tauri.app/start/prerequisites/)に従って確認してください。
- Windows 側のユーザーディレクトリ直下に `prelis-remote` を作成でき、npm と Cargo が必要な依存を取得できること。

Windows SSH の既定シェルが日本語の CP932 でエラーを返す環境では、[Mutagen 用 SSH ラッパー](../../scripts/mutagen-ssh/ssh)がエージェント検出時に Mutagen が認識できる英語エラーを返します。このラッパーはこのリポジトリ専用の Mutagen デーモンにだけ適用されます。

## 同期と成果物

送信元は Ubuntu のリポジトリ、送信先は `builduser@192.168.1.10:prelis-remote`（`C:\Users\builduser\prelis-remote`）です。同期モードは `one-way-safe` です。Git 管理情報、依存やビルドの生成物、`.env`、ローカル設定などは同期しません。Windows 側の `node_modules` と `target` は Windows で生成して再利用します。

NSIS インストーラーは Windows 側の `prelis-remote\apps\desktop\src-tauri\target\release\bundle\nsis\PrelisDesktop_<version>_x64-setup.exe`、MSI インストーラーは `prelis-remote\apps\desktop\src-tauri\target\release\bundle\msi\*.msi` に生成されます。一括手順では `bundle` ディレクトリの内容を Ubuntu 側の同じ相対パスへ回収します。実行ファイル `prelis-remote\apps\desktop\src-tauri\target\release\desktop.exe` は回収しません。インストーラーの形式は [Tauri の Windows Installer](https://v2.tauri.app/distribute/windows-installer/) を参照してください。

Windows 向けの頒布には NSIS インストーラーの `*-setup.exe` または MSI インストーラーの `*.msi` を渡せます。`desktop.exe` はビルド確認用の成果物で、頒布する必要はありません。Ubuntu 向けには Windows のインストーラーではなく、[Ubuntu 版リリース手順](release.md)で作成する deb または AppImage を頒布します。

同期状態の確認には次を使います。

```sh
MUTAGEN_DATA_DIRECTORY="$PWD/.mutagen" mutagen sync list prelis-windows --long
```

`one-way-safe` の競合や同期エラーが出た場合は `mutagen sync list` の内容を確認してから Windows 側の該当ファイルを整理します。Windows 側のビルドは、同期が正常終了してから始めてください。

Windows 実機で両方のインストーラーを実行し、起動と主要機能、インストーラーとアプリのアイコンを確認してください。NSIS インストーラーとアンインストーラーのアイコンは `tauri.conf.json` の `bundle.windows.nsis` で指定しています。
