# ネイティブ E2E テスト

アプリを実際に起動し、UI 操作と期待結果の検証を行います。macOS の日記保存・再起動と、タイマーの試聴・1分後の終了音・リセット後の停止を検証します。

## 配置

| 配置 | 責務 |
| --- | --- |
| `platforms/apple/` | 独立した Xcode UI テストプロジェクト。アプリ本体をビルド・インストールする依存関係を持たない |
| `platforms/macos/` | パス指定による起動・終了、共通の待機、ウィンドウの画像・音声付き録画 |
| `platforms/macos/capture/` | ScreenCaptureKit の独立した撮影アプリ |
| `domains/diary/macos/` | 日記の画面操作と保存・再起動後の検証 |
| `domains/timer/macos/` | 音声ファイル追加・試聴・タイマー完了・リセットの UI 操作 |
| `domains/timer/audio-analysis.py` | 実際に収録した音声の周波数・タイミング・停止の判定 |
| `fixtures/diary/` | 固定の入力文章 |
| `fixtures/timer/` | 独自の合成2音 WAV |
| `../../scripts/e2e/` | 実行、入力・対象アプリの記録、結果の回収 |

別の機能は `domains/<機能名>/<OS>/` に追加します。機能固有の画面ヘルパーも同じ場所に置きます。iOS のフォルダ・ターゲットは実装時に追加します。

## 実行

リポジトリのルートで、対象のビルド済み `.app` を明示します。

```sh
bash scripts/macos/test-e2e.sh \
  --app /Users/kousei/prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/PrelisDesktop.app
```

Mac で実行するとローカルテストになります。Ubuntu から実行すると、`scripts/macos/.env` の `PRELIS_MACOS_SSH_HOST`・`PRELIS_MACOS_REMOTE_ROOT` を使い、新しい専用ディレクトリへテストコードだけを転送して実行します。既存の Mutagen 同期・アプリのビルドは実行しません。

既定は2件です。`--domain diary`・`--domain timer` で限定できます。`--record` を付けると対象アプリのウィンドウと音声だけを収録し、区間を結合した動画を保存・回収します。タイマーは録画指定の有無にかかわらず解析用の映像・音声を取得します。Xcode の全画面動画は出力しません。UI・音声解析・動画取得の結果は別々に記録し、必要な判定が1つでも失敗したら全体を失敗にします。

準備、認証、生成物、制約の詳細は [テスト運用](../../docs/development/testing.md) を参照してください。
