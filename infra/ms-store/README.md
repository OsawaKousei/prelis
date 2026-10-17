# Microsoft Store 用 MSI 配信

`PrelisDesktop_<version>_x64_en-US.msi` を、非公開 S3 バケットと CloudFront OAC から公開します。MS Store の Package URL は `https://prelis-windows-downloads.prj.kupac.co.jp/windows/<version>/PrelisDesktop_<version>_x64_en-US.msi` です。このホストは既存の `*.prj.kupac.co.jp` 証明書でカバーされます。

Microsoft は [HTTPS の直接リンク、バージョン付き URL、提出後に不変のバイナリ、オフラインで動くインストーラー](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)を要求しています。この構成は URL とファイルの配信部分を扱います。MSI 本体と含まれる PE の署名、サイレントインストール、オフラインでのインストールは Windows ビルド側で検証してください。

## 構成

- S3 はパブリックアクセスを遮断し、CloudFront distribution のみに `windows/` 以下の読み取りを許可します。
- CloudFront は HTTPS の GET/HEAD を提供します。ファイル名とパスにバージョンを含め、長期キャッシュを使います。
- S3 バケットはバージョニングを有効化します。`windows/` 以下の書き込みには `If-None-Match: *` を必須にし、同じキーの再アップロードと削除を拒否します。新しい版は必ず新しい URL にします。これらの保護はバケットポリシーの変更権限を持つ管理者には変更可能です。
- Terraform state は LP と別のキー、MSI は LP と別の S3 バケットと CloudFront distribution に置きます。

## `terraform init` の準備

リポジトリルートから、管理対象外のローカル設定を配置します。サンプルは既存の `infra/lp` と同じ AWS アカウント・profile・state バケットを使います。

```sh
cp infra/ms-store/backend.hcl.example infra/ms-store/backend.hcl
cp infra/ms-store/terraform.tfvars.example infra/ms-store/terraform.tfvars
```

AWS SSO セッションが切れた場合は `aws sso login --profile kupacllc` を実行します。`backend.hcl` と `terraform.tfvars` は Git 管理対象外です。

準備後の実行コマンド:

```sh
terraform -chdir=infra/ms-store init -backend-config=backend.hcl
terraform -chdir=infra/ms-store plan
terraform -chdir=infra/ms-store apply
```

`plan` では、このディレクトリ専用の S3 バケット、CloudFront、OAC、バケットポリシー、設定した場合のみ DNS レコードが新規作成されることを確認します。`apply` 後の `package_base_url` 出力を使います。既存の LP は変更しません。

## MSI の公開

署名付き Windows ビルドの回収と検証には [Windows ビルド手順](../../docs/development/windows.md)を使います。Tauri の Windows 設定は `offlineInstaller` なので、再ビルドには WebView2 オフラインインストーラーの取得が必要です。`publish-msi.py` は新しい署名レポートの `WebviewInstallMode = offlineInstaller`、`Valid`、タイムスタンプ、SHA-256 と MSI の実際の SHA-256 を照合し、存在しないキーにだけアップロードします。アップロード後に S3 の SHA-256 を照合して URL を表示します。古い署名レポートでは公開できません。

```sh
AWS_PROFILE=kupacllc python3 infra/ms-store/publish-msi.py \
  apps/desktop/src-tauri/target/release/bundle/msi/PrelisDesktop_0.1.0_x64_en-US.msi
```

表示された URL を `curl -fIL <package-url>` で確認し、`200 OK`、`Content-Type: application/x-msi`、正しいファイル名を確認してください。必要なら `curl -fL <package-url> -o /tmp/PrelisDesktop_0.1.0_x64_en-US.msi` で取得し、表示された SHA-256 と照合します。これらは `apply` とアップロードが完了するまで実行できません。

現在の `0.1.0` MSI は設定変更前に作られた 2.4 MB の成果物なので公開しないでください。[Tauri の説明](https://v2.tauri.app/distribute/windows-installer/)によれば既定方式はネットワークを必要とします。Store に提出する前に `offlineInstaller` で再ビルド・再署名した MSI を使用し、WebView2 のない環境でオフラインのサイレントインストールを検証してください。インストール時のダウンロードが発生する MSI は提出しないでください。
