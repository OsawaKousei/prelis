# Prelis Mobile

React Native のモバイルアプリです。
`App.tsx` は Safe Area などのアプリ全体の設定、`src/shell/` はホーム・下部タブ・画面切り替えを担当します。
各機能は `src/apps/diary/`・`timer/`・`password/` に配置し、`app.tsx` に状態管理と操作処理、`*-view.tsx` に React Native の表示を置きます。
共通 UI・テーマ・アイコンとネイティブ API の窓口は `src/shared/`、OS 固有のネイティブ処理は `android/` と `ios/` に配置しています。
共通処理は `@prelis/core`、デスクトップと共通の PNG アイコンは `@prelis/icons` を利用します。iOS は Simulator と実機で Metro を使った起動、実機の Fast Refresh を確認済みです。

- [構成と依存関係](../../docs/development/architecture.md)
- [デザインガイドライン](../../docs/design/guidelines.md)
- [Android のセットアップ・起動・ビルド](../../docs/development/android.md)
- [iOS Simulator・実機のセットアップと Metro 開発](../../docs/development/ios.md)
- [共通の作業・検証手順](../../docs/development/workflow.md)
- [AI エージェント向け案内](AGENTS.md)
