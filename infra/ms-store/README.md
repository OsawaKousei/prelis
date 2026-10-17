# Microsoft Store 用 MSI 配信

MSI インストーラーを、非公開 S3 バケットと CloudFront OAC から公開します。ホスト `prelis-windows-downloads.prj.kupac.co.jp` は既存の `*.prj.kupac.co.jp` 証明書でカバーされます。NSIS はこの S3 バケットへアップロードしません。

Microsoft Store の Package URL: `https://prelis-windows-downloads.prj.kupac.co.jp/windows/0.1.0/PrelisDesktop_0.1.0_x64_en-US.msi`

Microsoft は [HTTPS の直接リンク、バージョン付き URL、提出後に不変のバイナリ、オフラインで動くインストーラー](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)を要求しています。この構成は URL とファイルの配信部分を扱います。MSI 本体と含まれる PE の署名、サイレントインストール、オフラインでのインストールは Windows ビルド側で検証してください。

## 構成

- S3 はパブリックアクセスを遮断し、CloudFront distribution のみに `windows/` 以下の MSI の読み取りを許可します。
- CloudFront は HTTPS の GET/HEAD を提供します。ファイル名とパスにバージョンを含め、長期キャッシュを使います。
- S3 バケットはバージョニングを有効化します。`windows/` 以下の MSI の書き込みには `If-None-Match: *` を必須にし、同じキーの再アップロードと削除を拒否します。新しい版は必ず新しい URL にします。これらの保護はバケットポリシーの変更権限を持つ管理者には変更可能です。
- Terraform state は LP と別のキー、MSI は LP と別の S3 バケットと CloudFront distribution に置きます。

## Terraform の管理

2026-10-17 にこの構成を `kupacllc` アカウントへ適用済みです。Terraform state は S3 backend の `prelis/ms-store/terraform.tfstate`、公開用 S3 バケットは `prelis-ms-store-103492189525-ap-northeast-1` です。別の作業環境で初期化する場合は、リポジトリルートから管理対象外のローカル設定を配置します。サンプルは既存の `infra/lp` と同じ AWS アカウント・profile・state バケットを使います。

```sh
cp infra/ms-store/backend.hcl.example infra/ms-store/backend.hcl
cp infra/ms-store/terraform.tfvars.example infra/ms-store/terraform.tfvars
```

AWS SSO セッションが切れた場合は `aws sso login --profile kupacllc` を実行します。`backend.hcl` と `terraform.tfvars` は Git 管理対象外です。

初期化と、変更時の確認コマンド:

```sh
terraform -chdir=infra/ms-store init -backend-config=backend.hcl
terraform -chdir=infra/ms-store plan
```

`plan` で変更対象を確認してから `apply` します。既存の LP は別 state で管理します。

## MSI の公開

署名付き Windows ビルドの回収と検証には [Windows ビルド手順](../../docs/development/windows.md)を使います。`publish-msi.sh` は署名レポートの `WebviewInstallMode = offlineInstaller`、署名状態、タイムスタンプ、SHA-256 を照合し、MSI だけを存在しないキーにアップロードします。アップロード後に S3 の SHA-256 を照合して URL を表示します。同じ内容が既に公開済みなら再実行できます。違う内容で同じ URL を使うことはできません。

```sh
AWS_PROFILE=kupacllc ./infra/ms-store/publish-msi.sh \
  apps/desktop/src-tauri/target/release/bundle/msi/PrelisDesktop_0.1.0_x64_en-US.msi
```

表示された URL を `curl -fIL <URL>` で確認し、`200 OK`、`Content-Type: application/x-msi`、正しいファイル名を確認してください。必要なら `curl -fL <URL> -o /tmp/<ファイル名>` で取得し、表示された SHA-256 と照合します。

現在の `0.1.0` MSI は `offlineInstaller` で再ビルド・再署名済みです。Store に提出する前に WebView2 のない環境でオフラインのサイレントインストールを検証してください。インストール時のダウンロードが発生する MSI は提出しないでください。
