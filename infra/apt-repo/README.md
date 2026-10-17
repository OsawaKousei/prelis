# Prelis Desktop APT リポジトリ

`dist/apt-repo` に作成済みの署名付き APT リポジトリを、非公開 S3 バケットと CloudFront OAC から `https://prelis-apt-packages.prj.kupac.co.jp/apt/` で配信します。`prelis-archive-keyring.gpg`、`dists/stable/`、`pool/` だけを S3 の `apt/` 以下へ公開します。`conf/`、`db/`、GPG 秘密鍵は公開しません。

`infra/ms-store` と同じ AWS アカウント、`*.prj.kupac.co.jp` の ACM 証明書、Route 53 公開ゾーンを使います。S3 バケット、CloudFront distribution、Terraform state キーは APT 専用です。S3 はパブリックアクセスを遮断し、バージョニング、SSE-S3、Bucket owner enforced を設定します。CloudFront だけが OAC 経由で `apt/` を読み取れます。

CloudFront の `/apt/dists/*` はキャッシュを無効にし、`/apt/pool/*` は長期キャッシュします。公開鍵は 1 時間キャッシュします。公開順序は DEB、公開鍵、インデックス、`Release`、`Release.gpg`、`InRelease` です。古い DEB は削除せず、同じ S3 キーの内容が異なる場合は公開を中止します。複数ファイルの切り替えは原子的ではないため、更新中に新旧インデックスが混在する短い時間は残ります。

## Terraform の準備

Git 管理対象外のローカル設定を配置しています。サンプルの値は `infra/ms-store` の証明書・Route 53 ゾーンと同じです。AWS SSO セッションが切れた場合は `aws sso login --profile kupacllc` を実行してください。

```sh
terraform -chdir=infra/apt-repo init -backend-config=backend.hcl
terraform -chdir=infra/apt-repo plan
```

`plan` で APT 専用リソースだけが新規作成されることを確認してから `apply` してください。`init`、`plan`、`apply` はこの準備作業では実行していません。設定例から作り直す場合は `backend.hcl.example` を `backend.hcl`、`terraform.tfvars.example` を `terraform.tfvars` にコピーしてください。

## リポジトリの公開

`publish-apt.sh` は GPG 署名、`Release` のインデックスの SHA-256、`Packages` に記載された DEB の SHA-256 を検証します。公開には AWS CLI v2、Terraform、GnuPG の `gpgv`、Python 3 が必要です。署名作成に使う秘密鍵はローカルにのみ置き、S3 にはアップロードしません。

```sh
./infra/apt-repo/publish-apt.sh --verify-only
AWS_PROFILE=kupacllc ./infra/apt-repo/publish-apt.sh
```

スクリプトは適用済み Terraform state の出力からバケット名とリージョンを取得します。`terraform apply` と CloudFront のデプロイ完了後に公開してください。公開後は次を確認します。

```sh
curl -fI https://prelis-apt-packages.prj.kupac.co.jp/apt/prelis-archive-keyring.gpg
curl -fI https://prelis-apt-packages.prj.kupac.co.jp/apt/dists/stable/InRelease
curl -fsSL https://prelis-apt-packages.prj.kupac.co.jp/apt/dists/stable/InRelease -o /tmp/prelis-InRelease
gpgv --keyring dist/apt-repo/prelis-archive-keyring.gpg /tmp/prelis-InRelease
```

APT のパッケージ名は DEB 内の `prelis-desktop`、suite は `stable`、component は `main`、architecture は `amd64` です。利用者は公開鍵のフィンガープリント `6E2711636C689C79E2283BD9FF5A37D5E9D0457A` を公式の案内と照合してから、次のように登録できます。

```sh
curl -fsSL https://prelis-apt-packages.prj.kupac.co.jp/apt/prelis-archive-keyring.gpg \
  | sudo tee /usr/share/keyrings/prelis-archive-keyring.gpg >/dev/null
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/prelis-archive-keyring.gpg] https://prelis-apt-packages.prj.kupac.co.jp/apt stable main' \
  | sudo tee /etc/apt/sources.list.d/prelis.list >/dev/null
sudo apt update
sudo apt install prelis-desktop
```
