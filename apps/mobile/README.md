# Prelis Mobile

React Native のモバイルアプリです。
画面の切り替えは `App.tsx`、各機能の UI は `src/`、OS 固有のネイティブ処理は `android/` と `ios/` に配置しています。
共通処理は `@prelis/core`、デスクトップと共通の PNG アイコンは `@prelis/icons` を利用します。iOS は Simulator での起動まで確認済みです。

- [構成と依存関係](../../docs/architecture.md)
- [デザインガイドライン](../../docs/design/guidelines.md)
- [Android のセットアップ・起動・ビルド](../../docs/development/android.md)
- [iOS Simulator のセットアップ・ビルド](../../docs/development/ios.md)
- [共通の作業・検証手順](../../docs/development/workflow.md)
- [AI エージェント向け案内](AGENTS.md)
