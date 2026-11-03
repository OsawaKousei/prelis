# ネイティブ E2E テスト

アプリを実際に起動し、UI 操作と期待結果の検証を行います。現時点では macOS の日記保存・再起動テストを実装しています。

## 配置

| 配置 | 責務 |
| --- | --- |
| `platforms/apple/` | 独立した Xcode UI テストプロジェクト。アプリ本体をビルド・インストールする依存関係を持たない |
| `platforms/macos/` | パス指定による起動・終了、共通の待機、スクリーンショット |
| `domains/diary/macos/` | 日記の画面操作と保存・再起動後の検証 |
| `fixtures/diary/` | 固定の入力文章 |
| `../../scripts/e2e/` | 実行、入力・対象アプリの記録、結果の回収 |

別の機能は `domains/<機能名>/<OS>/` に追加します。機能固有の画面ヘルパーも同じ場所に置きます。iOS のフォルダ・ターゲットは実装時に追加します。

## 実行

リポジトリのルートで、対象のビルド済み `.app` を明示します。

```sh
bash scripts/macos/test-e2e.sh \
  --app /Users/kousei/prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/PrelisDesktop.app
```

Mac で実行するとローカルテストになります。Ubuntu から実行すると、`scripts/macos/.env` の `PRELIS_MACOS_SSH_HOST`・`PRELIS_MACOS_REMOTE_ROOT` を使い、新しい専用ディレクトリへテストコードだけを転送して実行します。既存の Mutagen 同期・アプリのビルドは実行しません。

`--record` を付けると、同じテストの成功時にも Xcode の画面記録を動画として保存・回収します。UI テストの成否と動画取得の成否は別々に記録します。

準備、認証、生成物、制約の詳細は [テスト運用](../../docs/development/testing.md) を参照してください。
