# Prelis LP

Prelis のデスクトップ・Android・ウェブ版で提供する Diary・Timer・Password と、各版の利用方法を紹介する静的サイトです。ウェブ版は他の利用環境と並べて選択でき、公開サイトへのリンクと簡潔な注意書きを表示します。デザインは [ガイドライン](../docs/design/guidelines.md)、機能説明は [仕様](../docs/specs/desktop-apps.md) に合わせています。

## ローカル確認

lp/frontend/app で実行します。

    npm ci
    npm run dev

ブラウザーで http://localhost:3000/ を開きます。静的サイトのビルドは npm run build です。

## デプロイ

公開 URL は https://prelis.prj.kupac.co.jp/ です。AWS リソースの定義と state 設定は [infra/lp](../infra/lp/README.md) にあります。

Terraform の適用後、リポジトリルートから AWS_PROFILE=kupacllc ./lp/deploy.sh で静的ファイルをビルドし、S3 に同期して CloudFront のキャッシュを無効化できます。同期時は Prelis 用バケット内の既存ファイルが置き換わります。
