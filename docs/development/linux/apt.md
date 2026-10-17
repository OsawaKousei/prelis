# Linux 向け APT での頒布

Prelis Desktop の Ubuntu amd64 向け `.deb` を署名付き APT リポジトリに登録・公開する手順です。`.deb` の作成と動作確認は[deb・AppImage のビルド](build.md)を参照してください。公開作業のコマンドはリポジトリのルートで実行します。

## 公開版をインストールする

Ubuntu amd64 で初めて利用する場合は、公開鍵の指紋が `6E2711636C689C79E2283BD9FF5A37D5E9D0457A` と一致することを確認してから登録します。既に Prelis の APT ソースを登録済みなら、最後の `apt update` と `apt install` だけで構いません。

```sh
curl -fsSLo /tmp/prelis-archive-keyring.gpg https://prelis-apt-packages.prj.kupac.co.jp/apt/prelis-archive-keyring.gpg
gpg --show-keys --with-fingerprint /tmp/prelis-archive-keyring.gpg
```

指紋を、鍵の取得先とは別に公開された値と照合してから続けます。

```sh
sudo install -D -m 0644 /tmp/prelis-archive-keyring.gpg /etc/apt/keyrings/prelis-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/prelis-archive-keyring.gpg] https://prelis-apt-packages.prj.kupac.co.jp/apt stable main' | sudo tee /etc/apt/sources.list.d/prelis.list >/dev/null
sudo apt update
sudo apt install prelis-desktop
```

既存の `prelis.sources` などがある場合は、同じリポジトリを重複登録しないでください。

## 現在の構成と鍵

| 項目 | 設定・参照先 |
| --- | --- |
| ローカルの管理原本 | `dist/apt-repo/`（`conf/`、`db/`、`dists/`、`pool/`） |
| suite / component / architecture | `stable` / `main` / `amd64`（[distributions](../../../dist/apt-repo/conf/distributions)） |
| APT でのパッケージ名 | `prelis-desktop`（`.deb` 内の `Package` フィールド） |
| 公開 URL | `https://prelis-apt-packages.prj.kupac.co.jp/apt/`（[Terraform の出力](../../../infra/apt-repo/main.tf)） |
| S3 の配置先 | Terraform 出力のバケット内の `apt/` 以下（[公開スクリプト](../../../infra/apt-repo/publish-apt.sh)） |
| APT メタデータ署名鍵 | `6E2711636C689C79E2283BD9FF5A37D5E9D0457A` |
| deb / AppImage の分離署名鍵 | `5985489712B7621E3FD07DEC77B8FD8948B3E363` |

APT は公開鍵と `InRelease` または `Release.gpg` の署名を使い、`Packages` と `.deb` のハッシュをたどって検証します。GitHub Releases 向けの `.deb.asc` は APT への登録・インストールには使いません。APT 用の秘密鍵はローカルの GnuPG に保持し、S3 や Git に置きません。S3 へ公開するのは `prelis-archive-keyring.gpg`、`dists/`、`pool/` です。

アプリ設定上のバージョンと APT リポジトリの登録版は別に確認します。設定上のバージョンが上がっていても、対応する `.deb` をビルド・登録・公開するまでは APT の配布版は変わりません。

## 配信基盤の設定

[Terraform 設定](../../../infra/apt-repo/main.tf)は APT 専用の非公開 S3 バケット、CloudFront OAC、Route 53 レコードを定義します。S3 にはパブリックアクセス遮断、バージョニング、SSE-S3 を設定し、CloudFront からだけ `apt/` 以下を読み取れるようにします。CloudFront の `/apt/dists/*` はキャッシュを無効にし、`/apt/pool/*` は長期キャッシュ、公開鍵は 1 時間キャッシュします。

初回構築またはインフラ設定の変更時は、[backend.hcl.example](../../../infra/apt-repo/backend.hcl.example) と [terraform.tfvars.example](../../../infra/apt-repo/terraform.tfvars.example) を元に、Git 管理対象外の `backend.hcl` と `terraform.tfvars` を用意します。サンプルは `infra/ms-store` と同じ AWS アカウント、ACM 証明書、Route 53 ゾーンを参照します。AWS SSO セッションが切れた場合は `aws sso login --profile kupacllc` を実行します。

```sh
terraform -chdir=infra/apt-repo init -backend-config=backend.hcl
terraform -chdir=infra/apt-repo plan
```

`plan` の変更内容を確認してから `apply` します。既存の配信基盤に新しい `.deb` を公開するだけなら Terraform の再適用は不要です。公開スクリプトは適用済み Terraform state の `bucket_name`、`aws_region`、`apt_base_url` を読み取ります。

## バージョンと更新の流れ

ビルド時は [Tauri 設定](../../../apps/desktop/src-tauri/tauri.conf.json)、[Cargo.toml](../../../apps/desktop/src-tauri/Cargo.toml)、[デスクトップの package.json](../../../apps/desktop/package.json) のバージョンを揃えます。[ビルドスクリプト](../../../scripts/linux/build-ubuntu.sh)は `package.json` の値を成果物のファイル名確認に使います。APT 公開スクリプトが読む版はファイル名や `package.json` ではなく、指定された `.deb` の制御情報にある `Version` です。

`--deb` を指定した公開スクリプトは、`dpkg-deb -f` で `Package`、`Version`、`Architecture` を読み、現在 `reprepro` に登録されている版より新しいことを Debian のバージョン比較で確認します。同じ版や古い版は登録前に停止します。`reprepro includedeb` がその `.deb` を `pool/` に登録し、`Packages` の `Version`、ファイル名、サイズ、SHA-256 を更新して `Release` と署名を作ります。現在の `stable` インデックスには新しい版が載り、旧版の `.deb` は S3 に保持します。

クライアントは `apt update` で署名付き `InRelease` と新しい `Packages` を取得し、`prelis-desktop` の候補版を更新します。インストール済みのアプリは、依存関係が満たされ保留されていなければ、`apt upgrade` または `apt install prelis-desktop` を実行したときに新しい版へ更新されます。`apt update` だけではアプリ本体は更新されません。APT ソースを登録していない直接配布の deb・AppImage は、この APT 更新の対象外です。

## 1. ビルド済み deb を確認する

[ビルド手順](build.md)に従い、対象 Ubuntu での動作を確認した `.deb` を用意します。APT と GitHub Releases に両方載せる場合は、同じファイルを使います。

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_${version}_amd64.deb"
test -f "$deb"
dpkg-deb -f "$deb" Package Version Architecture Depends
sha256sum "$deb"
```

`Package: prelis-desktop`、意図した `Version`、`Architecture: amd64`、対象 Ubuntu で解決可能な `Depends` を確認します。同じバージョン番号の `.deb` を内容だけ変えて再頒布しないでください。

## 2. 登録前の状態を確認する

`reprepro` と APT 専用の GPG 秘密鍵が必要です。`conf/distributions` の `SignWith` が上記 APT 鍵であることを確認します。登録とバックアップは公開スクリプトが行います。

```sh
repo_dir="$PWD/dist/apt-repo"
cat "$repo_dir/conf/distributions"
reprepro --basedir "$repo_dir" list stable
```

登録済みの同じバージョンがある場合は強制的に入れ直さず、ローカルの `.deb` と登録済みファイルの内容を調べます。

## 3. 公開前にローカルで検証する

```sh
gpg --show-keys --with-fingerprint "$repo_dir/prelis-archive-keyring.gpg"
./infra/apt-repo/publish-apt.sh --verify-only
```

公開鍵の指紋が上記 APT 鍵と一致することを確認します。`--verify-only` は現在のローカル原本について、`InRelease` と `Release.gpg` の署名、署名済みインデックス、および `Packages` に記載された `.deb` のサイズと SHA-256 を検証し、AWS へは接続しません。これはビルドしたアプリの起動や公開 URL からの取得を確認する操作ではありません。

## 4. S3 と CloudFront へ公開する

この節は公開作業時だけ実行します。CloudFront の `/apt/dists/*` はキャッシュ無効設定であることを確認してください。`--profile` には公開先の AWS profile、`--deb` にはビルド済み `.deb` を指定します。Terraform backend の設定にも profile がある場合は、同じ環境の state を参照する設定にします。スクリプトは AWS アカウントと Terraform 出力のバケット・リージョン・公開 URL を読み取り、現在の公開メタデータとローカル原本の一致を確かめてから登録します。

```sh
./infra/apt-repo/publish-apt.sh --profile kupacllc --deb "$deb"
```

公開スクリプトは `dist/apt-repo-backup.*` に現在の原本を保存し、`reprepro includedeb` で新しい `.deb` を登録・署名した後、ローカルの署名とハッシュを検証します。その後、`pool/` の `.deb`、公開鍵、`dists/stable/` のインデックス、`Release`、`Release.gpg`、最後に `InRelease` の順で S3 の `apt/` 以下へ反映します。新規アップロードする `.deb` には S3 の SHA-256 チェックサムを付けます。既存 `.deb` は同じ内容のときだけ再利用します。S3 に SHA-256 チェックサムが保存されていない既存 `.deb` はダウンロードしてバイト単位で比較し、そのオブジェクトにはチェックサムを追加しません。旧版の `.deb` は S3 から削除しません。公開先への複数オブジェクトの切り替えは原子的ではないため、更新中に新旧メタデータが混在する可能性があります。

最後に CloudFront 経由で `InRelease`、`Packages.gz`、新しい `.deb` をローカルと比較します。アップロード途中で失敗した場合、ローカルには登録済みの新バージョンが残ります。原因を直してから `--profile kupacllc` のみを指定して公開を再試行できます。CloudFront の無効化要求は実行しません。`conf/`、`db/`、GPG 秘密鍵もアップロードしません。

## 5. 公開後に検証する

CloudFront 経由の `InRelease` と公開鍵を取得し、指紋を別途確認済みの値と照合してから署名を検証します。URL は Terraform の実際の出力と一致させます。

```sh
apt_base_url="https://prelis-apt-packages.prj.kupac.co.jp/apt"
curl -fsSLo /tmp/prelis-archive-keyring.gpg "$apt_base_url/prelis-archive-keyring.gpg"
curl -fsSLo /tmp/prelis-InRelease "$apt_base_url/dists/stable/InRelease"
gpg --show-keys --with-fingerprint /tmp/prelis-archive-keyring.gpg
gpgv --keyring /tmp/prelis-archive-keyring.gpg /tmp/prelis-InRelease
```

別の Ubuntu amd64 テスト環境で[公開版のインストール手順](#公開版をインストールする)を実行し、`apt-cache policy prelis-desktop` で候補版、`sudo apt install --simulate prelis-desktop` で依存関係を確認します。実際のインストールと起動、更新版なら旧版からのアップグレードも確認します。

`Hash Sum mismatch` が出た場合は、公開中の `InRelease`、`Packages` と S3 の配置順序、CloudFront の `/apt/dists/*` のキャッシュ設定を調べます。`404` は公開 URL の `/apt/` と S3 の `apt/` の対応を確認します。旧版へ単純に戻しても APT は自動的にはダウングレードしないため、修正版はより大きなバージョン番号で頒布します。
