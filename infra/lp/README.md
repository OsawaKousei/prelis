# Prelis LP インフラ

公開 URL: https://prelis.prj.kupac.co.jp/

Prelis LP を非公開 S3 バケットと CloudFront OAC で配信します。Route 53 の公開ゾーン kupac.co.jp に A / AAAA alias レコードを作ります。サイトのビルド・アップロード手順は [lp](../../lp/README.md) を参照してください。

## 参照元との関係

lp/infra は Web to Markdown 用の参考設定です。Prelis には専用の Terraform state キー webpage/prelis-lp/terraform.tfstate、S3 バケット、CloudFront distribution、DNS レコードを使用します。証明書 ARN だけを共有します。Web to Markdown の state とリソースは変更しません。lp/infra は指定どおり残しており、確認後に手動で削除できます。

## terraform init の準備

Git 管理対象外の backend.hcl と terraform.tfvars を配置済みです。共有可能な設定例は同名の .example ファイルにあります。AWS profile は kupacllc、S3 backend は既存の state バケット、証明書は us-east-1 のワイルドカード証明書です。

2026-10-17 に AWS 認証と state バケットへの読み取りアクセス、Route 53 の公開ゾーン、発行済み証明書が *.prj.kupac.co.jp をカバーすることを確認しました。Prelis 用 state キー・S3 バケット・DNS レコードは、この確認時点では未使用でした。SSO セッションが切れた場合は aws sso login --profile kupacllc で再ログインしてください。

リポジトリルートから実行します。

    terraform -chdir=infra/lp init -backend-config=backend.hcl
    terraform -chdir=infra/lp plan

plan で Prelis 専用リソースの新規作成だけが表示されることを確認してから適用してください。この準備作業では init、apply、サイトのアップロードは実行していません。
