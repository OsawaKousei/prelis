# Prelis Web 配信インフラ

公開予定 URL: https://app-prelis.prj.kupac.co.jp/

`apps/web` の静的ビルドを、非公開 S3 バケットと CloudFront OAC から配信します。Route 53 に A / AAAA alias を作り、既存の `*.prj.kupac.co.jp` 証明書を共有します。拡張子のないパスは CloudFront Function で `index.html` に書き換え、存在しない画像や JavaScript に HTML を返さない構成です。`index.html` は短いキャッシュ、ハッシュ付きアセットは長いキャッシュで公開します。

Terraform state、S3 バケット、CloudFront distribution、DNS レコードは、このウェブ版専用です。既存の LP や MSI 配信の state とリソースは変更しません。

## `terraform init` 前の準備

Git 管理対象外の `backend.hcl` と `terraform.tfvars` を、同名の `.example` から用意します。サンプルは既存インフラと同じ `kupacllc` profile、state バケット、Route 53 公開ゾーン、us-east-1 のワイルドカード証明書を使用します。

2026-10-18 に AWS アカウント `103492189525` への読み取りアクセスを確認しました。証明書は発行済みで対象ドメインをカバーし、`app-prelis.prj.kupac.co.jp` の Route 53 レコードと CloudFront alias、専用 state キー、公開用バケット名は未使用でした。

この作業では Terraform の初期化、plan、apply、ファイルのアップロードは実行していません。次にリポジトリルートから実行するコマンドは次のとおりです。

```sh
terraform -chdir=infra/web-frontend init -backend-config=backend.hcl
terraform -chdir=infra/web-frontend plan
```

plan でウェブ版専用リソースの新規作成だけが表示されることを確認してから apply します。AWS SSO セッションが切れている場合は `aws sso login --profile kupacllc` が必要です。

## 適用後の公開

Terraform 適用後、リポジトリルートで `./infra/web-frontend/publish-web.sh` を実行します。スクリプトはウェブ版をビルドし、アセットを先に S3 へ置き、最後に `index.html` を更新して CloudFront を無効化します。以前のハッシュ付きアセットは残し、開いている古いタブの読み込みを妨げません。公開 URL で Diary、Timer、Password の主要操作とブラウザー内の保存を確認してください。
