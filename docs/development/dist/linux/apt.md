# Linux 向け APT での頒布

Prelis Desktop の検証済み `.deb` を KUPAC 公式 APT レジストリの管理者へ提出し、公開を依頼する手順です。Prelis 側ではビルド・成果物署名・動作確認と提出までを行い、登録・APT メタデータ署名・配信基盤の運用は管理者が [apt-repo](https://github.com/KUPAC-LLC/apt-repo) で行います。

`.deb` の作成は [deb・AppImage のビルド・署名](sign.md)、利用者向けの登録・インストールは [README の APT 手順](../../../../README.md#apt)を参照してください。

## 公開先と提出対象

| 項目 | 値 |
| --- | --- |
| 公式 APT URL | `https://packages.kupac.co.jp/apt/` |
| 製品 ID / パッケージ名 | `prelis` / `prelis-desktop` |
| suite / component / architecture | `stable` / `main` / `amd64` |
| 現在の対象 OS | Ubuntu 24.04（manifest では `ubuntu-24.04`） |
| 成果物の署名鍵 | `5985489712B7621E3FD07DEC77B8FD8948B3E363` |
| APT メタデータ署名鍵 | `6E2711636C689C79E2283BD9FF5A37D5E9D0457A` |

管理者には、対象 Ubuntu 上で確認した deb を渡します。GitHub Releases にも載せる場合は同じファイルを使用し、APT 管理側では再ビルドしません。同じパッケージ名・版・architecture の内容を差し替えず、修正時はバージョンを上げてビルドし直します。

## 1. 提出する成果物を確認する

[デスクトップのバージョン更新](../../desktop.md#バージョンを揃える)と [ビルド・署名手順](sign.md)に従って deb と分離署名を作成します。以下は Prelis リポジトリのルートで実行します。

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="dist/linux/v${version}/PrelisDesktop_${version}_amd64.deb"
test -f "$deb"
test -f "${deb}.asc"
dpkg-deb -f "$deb" Package Version Architecture Depends
stat --format='%s' "$deb"
sha256sum "$deb" "${deb}.asc"
gpg --verify "${deb}.asc" "$deb"
```

`Package: prelis-desktop`、意図した `Version`、`Architecture: amd64` と、対象 OS で依存関係を解決できることを確認します。署名が有効であり、署名鍵の指紋が上記の成果物署名鍵と一致することも確認します。

ビルド元のリポジトリ URL・タグ・40桁のコミット SHA は、実際にその deb をビルドした時点の値を記録します。提出時の checkout の HEAD を無条件に転記しないでください。

## 2. 動作確認の記録を用意する

対象の Ubuntu 24.04（amd64）で以下を確認し、`verification.md` としてまとめます。

| manifest の checks | 確認する内容 |
| --- | --- |
| `install` | Prelis 未導入の環境へ提出する deb をインストールし、依存関係を解決して導入が完了する |
| `launch` | 導入した版が起動し、表示バージョンと日記・タイマー・パスワード生成の主要操作が正しい |
| `upgrade` | 旧版から提出する deb へ更新でき、起動と保存済みデータの継続利用ができる |

記録には実施日、Ubuntu の版と architecture、確認者、旧版と更新先の版、操作と結果、ビルド元、deb のサイズと SHA-256、署名検証結果を含めます。未確認の項目を `passed` とせず、未実施・失敗が残る場合は公開依頼前に解消します。レジストリは3項目すべてが `passed` の成果物を受け付けます。

## 3. 管理者に渡すファイルと情報

| 提出物 | 保存先・内容 |
| --- | --- |
| deb 本体 | `dist/linux/v<version>/PrelisDesktop_<version>_amd64.deb` |
| deb の分離署名 | 上記と同じ名前に `.asc` を付けたファイル |
| 成果物署名用の公開鍵 | `dist/github-release/v<version>/prelis-release-signing-key.asc`。指紋を別途伝える |
| チェックサム一覧 | `dist/github-release/v<version>/sha256sums.txt`。提出する deb・署名・公開鍵の値が一致することを確認 |
| 動作・出所の確認記録 | 前節の `verification.md` |

AppImage は APT への登録対象ではありません。公開鍵は提出できますが、秘密鍵・パスフレーズ・AWS 認証情報は提出物に含めません。

管理者が manifest を作成できるよう、次の情報も公開依頼へ添えます。

| manifest の項目 | 提出する値 |
| --- | --- |
| `product` / `source_repository` | `prelis` / `https://github.com/OsawaKousei/prelis` |
| `source_tag` / `source_commit` | 実際のビルド元タグと40桁のコミット SHA |
| `package` / `version` / `architecture` | deb 内の `Package`・`Version`・`Architecture` |
| `suite` / `component` | `stable` / `main` |
| `size` / `sha256` | 提出する deb の実測値 |
| `tested_os` / `verified_by` | `ubuntu-24.04` / 実際の確認者 |
| `checks` | `install`・`launch`・`upgrade` の確認結果と、その根拠の記録 |

`artifact_url` は、管理者が受領した deb を置くローカル絶対パスの `file:///...` URI です。製品側の作業パスや GitHub のダウンロード URL をそのまま manifest に入れず、受領先が決まった後に管理者が設定します。`verification_record` も管理リポジトリ内に配置した確認記録のパスに合わせます。

## 4. 成果物を提出して公開を依頼する

管理者と合意したファイル共有先や添付方法で、上記のファイルと情報を渡します。GitHub Releases の Assets を受け渡し元にする場合は、対象タグ、取得する各ファイルの URL、サイズ、SHA-256 を明示し、必要な署名や公開鍵が実際に取得できることを確認します。Release に未添付のファイルは、合意した別の方法で渡します。

公開依頼は次の形式を基本にし、括弧内を実際の値に置き換えます。

```text
件名: Prelis Desktop <version> の APT 公開依頼

公開先: https://packages.kupac.co.jp/apt/
登録対象: prelis / prelis-desktop / <version> / amd64 / stable / main
対象 OS: ubuntu-24.04
ビルド元: https://github.com/OsawaKousei/prelis
タグ: <実際のビルド元タグ>
コミット SHA: <実際のビルド元の40桁 SHA>
成果物の受け渡し先: <共有先、または添付ファイル一覧>
deb のサイズ: <bytes>
deb の SHA-256: <実測値>
成果物署名鍵: 5985489712B7621E3FD07DEC77B8FD8948B3E363
確認者: <氏名または管理用 ID>
動作・出所の確認記録: verification.md
install: <実施日と結果>
launch: <実施日と結果>
upgrade: <更新元・更新先・実施日と結果>

添付: deb、deb.asc、成果物署名用の公開鍵、チェックサム一覧、verification.md
署名・出所・動作確認記録を確認の上、登録・公開をお願いします。
公開完了後に、公開 URL、パッケージの版、公開世代 ID と確認結果をお知らせください。
```

管理者は受領した deb と分離署名を管理リポジトリの `artifacts/prelis/v<version>/` に保存し、`records/releases/prelis-desktop/<version>/amd64/` に `manifest.json` と `verification.md` を用意します。出所・署名・許可設定・manifest を確認した後、管理リポジトリの公開手順で登録・公開します。Prelis 側から APT 原本や配信基盤を操作する必要はありません。

管理者向けの正本は、管理リポジトリの [公開手順](https://github.com/KUPAC-LLC/apt-repo/blob/main/docs/publish.md)、[manifest テンプレート](https://github.com/KUPAC-LLC/apt-repo/blob/main/records/templates/release.manifest.json.example)、[記録の構成](https://github.com/KUPAC-LLC/apt-repo/blob/main/records/README.md)です。これらは非公開リポジトリへのアクセス権が必要です。

## 5. 公開完了を確認する

管理者から公開完了の連絡と対象版・公開世代 ID・確認結果を受け取ります。[README の APT 手順](../../../../README.md#apt)で公式レジストリを登録した別の対象 Ubuntu 環境で、公開版の候補と依存関係を確認します。

```sh
sudo apt update
apt-cache policy prelis-desktop
sudo apt install --simulate prelis-desktop
```

候補版と取得先が公開依頼した版・公式 URL に一致することを確認し、実際のインストール・起動・旧版からの更新も確認します。結果と公開世代 ID をリリースの記録に残します。失敗時は管理者へ対象版と結果を連絡し、同じ版を内容だけ変えて再提出しないでください。
