# モバイルのエージェント向け案内

対象は `apps/mobile/` の React Native UI、Metro 設定、ネイティブプロジェクトです。
現在は Android の開発・検証を行い、iOS 対応は保留しています。
[基本原則](../../AGENTS.md)に沿って、デスクトップで確認済みの機能を反映します。
UI はモバイル向けに個別に開発し、画面構成や操作方法を端末の特徴に合わせます。

- [共通の開発規則](../../docs/development/rules.md)
- [構成と責務の境界](../../docs/architecture.md)
- [Android の環境・起動・ビルド手順](../../docs/development/android.md)
- [変更内容に応じた検証](../../docs/development/workflow.md)
- [機能仕様の索引](../../docs/specs/README.md)

共有ロジックも変更する場合の入口は [core の指示](../../packages/core/AGENTS.md) です。
