# Prelis Mobile

React Native 0.87.1 のモバイルアプリです。現在は Android の開発環境を対象としています。

必要な SDK・JDK と起動手順は[ルートの README](../../README.md)を参照してください。
リポジトリのルートで `npm run start:mobile` を起動し、別のターミナルで
`npm run android -- --no-packager` を実行します。
共有ロジックは `@prelis/core` から import し、Metro がソースを直接取り込みます。

iOS のネイティブ設定・ビルド検証は保留中です。
