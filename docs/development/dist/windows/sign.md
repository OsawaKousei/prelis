# Windows の署名付きビルド

Ubuntu からソースを同期し、Windows のログオン済み GUI セッションで NSIS・MSI のビルドと署名を行い、検証済み成果物を回収します。環境準備と通常の開発起動は [desktop.md](../../desktop.md) を参照してください。

## 起動方法と操作

Ubuntu の `scripts/windows/.env` に SSH 接続先と署名情報を設定します。[.env.example](../../../../scripts/windows/.env.example) のキーを使い、サービスプリンシパルには対象プロファイルの Artifact Signing Certificate Profile Signer ロールを付与します。Windows には Artifact Signing Client Tools、Node.js・Rust・MSVC・WebView2・MSI ビルド用の VBScript が必要です。

実行時は Ubuntu のリポジトリルートで次を使います。

```sh
./scripts/windows/build-windows.sh
```

スクリプトが SSH トンネルを開始して同期した後、VNC クライアントで `127.0.0.1:22118` に接続し、SSH 接続先と同じユーザーで Windows の GUI にログインします。既にログオン済みならビルドが自動で始まります。PowerShell へのコマンド貼り付けや、ビルド後の Enter 操作は不要です。

対象ユーザーの Explorer が存在するセッションを WTS API のユーザー名・ドメインから SID に照合します。他ユーザーの GUI ログオンでは開始しません。同一ユーザーの GUI セッションが複数ある場合は、1つに絞るようエラーを返します。ビルド中は対象ユーザーからサインアウトしないでください。

VNC トンネルはスクリプト終了時に閉じます。回収後の UI 確認には実機または RustDesk などで対象ユーザーのデスクトップを操作します。サイドバーのバージョン表示と、日記の保存・再読込、タイマーの音声を確認します。

## 構成と公式仕様

操作の入口は `scripts/windows/` 直下に置き、内部処理は `scripts/windows/internal/` にまとめます。

| ファイル | 責務 |
| --- | --- |
| `scripts/windows/create-windows-sync.sh` | Windows 側へのソース同期 |
| `scripts/windows/build-windows.sh` | トンネル、同期、認証情報の転送、制御スクリプトの呼び出し、ログ・成果物の回収 |
| `scripts/windows/invoke-build-task.ps1` | GUI ログオン待機、COM API によるタスク登録・起動、完了監視、停止・後片付け |
| `scripts/windows/verify-artifact-report.py` | 回収した成果物のレポート・SHA-256・バージョン照合と集約 |
| `scripts/windows/internal/run-build-task.ps1` | GUI セッション内での実行ユーザー確認、ビルド呼び出し、秘密値を伏せたログと結果の保存 |
| `scripts/windows/internal/build-task-common.ps1` | 実行 ID ごとのパス、結果 JSON の書き込み、一時署名ファイルの削除 |
| `scripts/windows/internal/build.ps1` | npm 依存の導入、Tauri の署名付き NSIS・MSI 生成、署名検証 |
| `scripts/windows/internal/receive-credentials.ps1` | SSH の標準入力から一時署名認証情報を受信 |
| `scripts/windows/internal/sign-artifact.ps1` | Tauri の署名フックとアプリ本体の署名 |
| `scripts/windows/internal/verify-signatures.ps1` | Windows 上の署名・ファイルバージョン検証とレポート生成 |
| `scripts/windows/internal/desktop-version.py` | ビルド前のデスクトップ版バージョン照合 |
| `scripts/windows/internal/read-windows-env.sh` | Ubuntu 側での接続・署名設定の読み込み |

タスクのログオン方式は `TASK_LOGON_INTERACTIVE_TOKEN`（3）、実行権限は `TASK_RUNLEVEL_LUA`（0）です。Microsoft は、この方式を「既にログオンしたユーザーの既存の対話セッションで実行する」と定義しています。[TASK_LOGON_TYPE](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_logon_type)

`RunEx` に `TASK_RUN_USE_SESSION_ID`（0x4）を渡して GUI セッションを明示します。タスクのトリガーは登録せず、`AllowDemandStart` を有効にして起動します。[IRegisteredTask::RunEx](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-iregisteredtask-runex)、[AllowDemandStart](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-allowdemandstart)

同一ユーザーの対話ログオン方式で登録するため、Windows パスワードの保存や管理者権限への昇格は行いません。この条件のパスワード要否とタスク操作権限は [Security Contexts for Tasks](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks) に従います。

PowerShell の `-NonInteractive` は入力プロンプトをエラーにする指定です。タスク自体は GUI セッション内で実行されます。[about_PowerShell_exe](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1#-noninteractive)

タスク操作には公式 COM API を使います。環境変数による Artifact Signing 認証には `ExcludeCredentials` を設定し、他の資格情報へのフォールバックを抑止します。[署名統合の認証仕様](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations#authentication)

Windows PowerShell 5.1 では、リダイレクトした外部コマンドの標準エラーが `ErrorRecord` として扱われます。npm・ビルド・署名検証の外部コマンド実行中は `ErrorActionPreference = Continue` とし、終了コードで成功・失敗を判定します。進捗を標準エラーに出すツールでもログを取得できるようにするためです。[外部コマンドと ErrorActionPreference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables#erroractionpreference)

## 成果物・ログと失敗時の挙動

実行 ID は32桁の英小文字16進数です。Windows 側のタスク名は `prelis-build-<id>`、ログと結果は `%USERPROFILE%\prelis-build-jobs\<id>\build.log`・`result.json` です。結果には実行 ID、状態、終了コード、ユーザー SID、セッション ID、開始・終了時刻、エラーを記録します。

Ubuntu 側のログは `apps/desktop/src-tauri/target/release/windows-build-logs/<id>/` に回収します。ビルド用の `release/bundle/` を経由し、最終成果物を Linux 版と同じくバージョン別のディレクトリに集約します。

結果 JSON の実行 ID・成功状態・終了コード、署名レポート、SHA-256、期待するバージョンを照合してから集約します。同じバージョンで再実行するとそのバージョンのディレクトリを入れ替え、別バージョンは保持します。検証または入れ替えの失敗時には既存の同バージョンの集約先を保持・復元します。`dist/windows/` の成果物は Git 管理対象外です。

署名レポートの `Path` は Windows の元の bundle 内の相対パス（`nsis/...`・`msi/...`）を維持します。集約先で検証する場合はフラット配置を指定します。

```sh
python3 scripts/windows/verify-artifact-report.py dist/windows/v0.1.3 \
  --report-name windows-prelis-signature-report.json --expected-version 0.1.3 --flat-layout
```

開始前に `desktop-version.py` がデスクトップの npm・Tauri・Cargo 設定、npm・Cargo ロック、サイドバー表示の6箇所を照合します。Windows でも npm・Tauri・Cargo のバージョンを照合し、署名検証時にアプリ本体と NSIS の EXE ファイルバージョン、MSI の `ProductVersion` を読み取ります。署名レポートの `Version`・`ApplicationVersion` と各ファイルの `Version` に記録し、Ubuntu 側でファイル名と集約先のバージョンまで照合します。EXE の数値バージョン `0.1.3.0` は `0.1.3` に正規化します。[MSI ProductVersion](https://learn.microsoft.com/en-us/windows/win32/msi/productversion)

子スクリプトの表形式出力は1つの `Out-String -Stream` パイプラインで文字列に変換します。結果 JSON の読み取りは UTF-8 を明示します。[Out-String](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/out-string?view=powershell-5.1)、[Windows PowerShell の文字コード](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)

Ubuntu 側の Ctrl+C・終了要求・失敗時は、その実行 ID の停止を Windows に要求します。停止処理はタスクのユーザーと実行内容、ワーカーの PID・開始時刻・セッションを照合し、`taskkill /T /F` でビルドのプロセスツリーを終了してから一時タスク・認証情報・署名設定を削除します。ワーカーの開始時刻は PID 再利用時の誤停止を避けるために使います。[taskkill の公式仕様](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/taskkill)

停止を確認できない場合は一時認証情報を残し、実行 ID と回復が必要な旨を表示します。Windows への接続が回復したら、同じユーザーで次を実行します。

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$env:USERPROFILE\prelis-remote\scripts\windows\invoke-build-task.ps1" -BuildId "<32桁の実行ID>" -Operation Stop
```

ログと結果は調査用に残ります。不要になった実行 ID のディレクトリは、タスクが終了したことを確認してから削除してください。Ubuntu と Windows それぞれに多重実行用のロックがありますが、ビルド中のソース編集や別環境からの同期は避けてください。
