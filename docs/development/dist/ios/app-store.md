# App Store での頒布

署名・検証済みの IPA を App Store Connect へ提出し、TestFlight 配信、App Store の審査・公開、配信後の確認を行う手順です。
コマンドは、特記がない限り Ubuntu 側のリポジトリルートで実行します。ビルド環境・配布用証明書・成果物の作成と検証は [iOS 配布物のビルド・署名](sign.md)を参照してください。
掲載文と画像の保存先は [iOS App Store 掲載素材](../../../../dist/app-store-ios/README.md)です。

## 必要な環境と設定

- Apple Developer Program の登録と、App Store Connect の対象アプリ `jp.co.kupac.prelis` を操作できるアカウントを用意します。既存アプリの更新には同じ登録を使用します。macOS デスクトップ版のアプリ登録・提出物とは区別します。
- アップロードに必要な権限と、審査提出に必要な Account Holder・Admin・App Manager のいずれかの権限を確認します。契約など App Store Connect の未完了項目を解消します。
- [署名の準備](sign.md#署名の準備)と成果物のローカル検証を完了します。提出に使用する Xcode / SDK の条件は [Apple のアップロード要件](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)を提出時に確認します。

### アップロード用の認証と提出物

| 内容 | 設定・保存先 |
| --- | --- |
| API キー ID | Ubuntu の `scripts/ios/.env` の `PRELIS_APPSTORE_API_KEY_ID` |
| API Issuer ID | 同ファイルの `PRELIS_APPSTORE_API_ISSUER_ID` |
| API 秘密鍵 | Mac 上の `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` |
| 提出用 IPA | `dist/ios/v1.0.1/build-2/all/appstore/PrelisMobile.ipa` |
| IPA の照合に使う一覧 | `dist/ios/v1.0.1/build-2/all/SHA256SUMS` |
| 掲載文・画像 | `dist/app-store-ios/text.md` と同ディレクトリの画像 |

API キーは対象アプリのアップロードに使用できるものを用意します。`.p8` の内容を `.env` に書き込んだり Ubuntu へコピーしたりしません。
認証情報は iOS 用設定へ記載します。移行期間は未指定の API 情報に従来の macOS 設定を利用できます。IPA の照合先は iOS 専用の Mac 同期先です。

## 1. 提出する IPA を作成・確認する

[パッケージ作成](sign.md#1-パッケージを作成する)と[成果物・署名の確認](sign.md#2-成果物と署名を確認する)を行います。
ビルド元のコミットとタグ、公開バージョン・ビルド番号、IPA の SHA-256、署名・プロファイルと動作確認の記録を残します。ビルド番号は App Store Connect の提出履歴と照合し、更新方法は [モバイル開発](../../mobile.md#バージョンを揃える)を参照してください。

```sh
# バージョンとビルド番号を提出対象に合わせます。
ipa=dist/ios/v1.0.1/build-2/all/appstore/PrelisMobile.ipa
test -f "$ipa"
sha256sum "$ipa"
./scripts/ios/upload-appstore.sh --validate-only "$ipa"
```

`--validate-only` も App Store Connect と通信します。[upload-appstore.sh](../../../../scripts/ios/upload-appstore.sh) は、指定 IPA のハッシュを一覧と照合し、Mac 上の同じ版・ビルドの `dist/ios/` にある IPA を一時コピーして、そのハッシュとも一致することを確認します。
そのコピーについて実機用 arm64、Bundle ID、バージョン、JavaScript・アセット、署名、プロファイルの有効期限、証明書との対応、配布用 Entitlements を確認した後、`xcrun altool --validate-app` を実行します。

スクリプトはソース同期・ビルド・IPA の転送・再署名を行いません。対象の `dist/ios/v<version>/build-<build>/all/` と、対応する Mac 側の同じ版・ビルドを保持します。新しいビルドを作っても過去ビルドのディレクトリは残ります。同じ版・ビルドを作り直して IPA が変わった場合はハッシュ不一致で停止します。従来の `apps/mobile/ios/build/release/all/appstore/PrelisMobile.ipa` と対応する作業用ハッシュ一覧も引き続き指定できます。

## 2. IPA をアップロードして処理完了を確認する

```sh
./scripts/ios/upload-appstore.sh \
  dist/ios/v1.0.1/build-2/all/appstore/PrelisMobile.ipa
```

前節のローカル照合と Apple 側の検証を再実行し、成功した場合だけ、検証した同じ一時コピーを `xcrun altool --upload-app` で送信します。エラー時は停止し、自動再試行しません。[Apple のアップロード手順](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)も参照してください。

1. App Store Connect の対象アプリで、アップロードした公開バージョン・ビルド番号と Apple 側の処理状態を確認します。
2. 処理失敗・警告・通知を確認し、署名・SDK・プライバシーマニフェストなどの指摘を解消します。修正して再ビルドする場合は新しいビルド番号を使用します。
3. 処理完了後、TestFlight の対象ビルドとして表示されることを確認し、暗号化輸出規制などの未完了項目に回答します。

アップロード成功と、処理完了・テスト配信可能・審査提出済みの状態はそれぞれ確認します。

## 3. TestFlight からインストールして確認する

1. TestFlight のテスト情報に、変更内容・確認する機能・連絡先を入力します。
2. 内部テストのグループに対象ビルドとテスターを追加します。外部テストを行う場合はグループ・招待方法を設定し、必要な TestFlight App Review と配信準備を完了します。
3. テスターが実機の TestFlight で招待を受け、対象バージョン・ビルド番号を確認してインストールします。

グループ・招待・外部テスト審査の条件は [TestFlight の公式手順](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)に従います。TestFlight の審査通過を App Store 本公開の審査通過として扱いません。

Metro を停止した状態で、配信版について次を確認します。

- 新規インストール・起動、アプリアイコンと対象ビルドが正しいこと。iPhone と、配信対象に含む iPad で確認すること。
- 日記の保存・日付移動・アプリ再起動後の再読込、日本語・絵文字、未保存本文の扱いが正しいこと。
- タイマーの開始・一時停止・再開・タブ切替中の計時・完了音・リセットと、ファイル選択画面からの音声追加・キャンセル・試聴・削除・選択の再読込ができること。
- パスワード生成の文字種・文字数と、別アプリへのコピーが正しいこと。
- [ウィンドウの互換性要件](../../mobile.md#ウィンドウの互換性要件)を実機の配信版でも満たすこと。
- 旧配信版から更新して起動し、現行 Expo 版同士では保存データを継続利用できること。旧 CLI 版からの自動データ移行がない制約は、[仕様](../../../specs/v0.1.3.md#移植方針)に従って別途記録・案内すること。

クラッシュ・テスターのフィードバックを確認します。テスト後にコードを変更した場合は、新しいビルド番号で生成・アップロード・配信確認をやり直します。App Store の審査には確認した同じビルドを選択します。

## 4. 掲載情報を整えて審査に提出する

[掲載素材の README](../../../../dist/app-store-ios/README.md) と [text.md](../../../../dist/app-store-ios/text.md)を基に準備します。保存済みの素材は旧版 `1.0 (1)` の Debug ビルドを基にしています。現行の公開バージョン・リング表示・折りたたみ構成などと照合し、説明とスクリーンショットを提出ビルドに合わせます。

| 内容 | 確認すること |
| --- | --- |
| アプリ情報・掲載文 | アプリ名、説明、キーワード、カテゴリ、年齢制限指定、サポート URL、著作権、更新内容 |
| 画像 | 対象 iPhone / iPad のスクリーンショット、提出ビルドの AppIcon、必要な画像のサイズと形式 |
| プライバシー | 公開するポリシー URL、依存 SDK を含む実際のデータの扱いと App Privacy の回答 |
| 暗号化輸出規制 | 提出ビルドと依存ライブラリの暗号化利用に対応する回答・必要書類 |
| 審査用情報 | 連絡先、サインインの要否、主要機能の操作説明、バックグラウンド動作やデータ移行の制約 |
| 配信・公開設定 | 国・地域、価格、対象端末、手動公開・自動公開などの公開タイミング |

端末内保存という説明だけで App Privacy の回答を確定せず、日記・取込音声・クリップボード・依存 SDK・ネットワーク通信の扱いを確認します。[App Privacy の公式手順](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)に沿って回答し、プライバシーポリシーとサポート URL に到達できることを確認します。

App Store Connect の iOS バージョン記録にテスト済みビルドを選択し、掲載情報と未完了項目を確認して「審査用に追加」します。続いて提出内容を確認し、「審査へ提出」まで実行します。追加しただけでは審査に送信されません。[Apple の審査提出手順](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)を参照してください。
審査結果を確認し、承認後は設定した公開方法に従ってリリースします。指摘への対応でビルドを変更した場合は、差し替えるビルドの配信確認もやり直します。

## 5. 公開した版を確認する

1. App Store Connect の公開状態と対象バージョンを確認し、一般利用者向けの App Store 掲載ページから掲載文・画像・配信対象を確認します。
2. 対象地域・端末の App Store から新規インストールと旧版からの更新を確認します。TestFlight での確認だけでは公開後の確認を完了としません。
3. 起動・主要操作・クラッシュの状況を確認し、公開日時、公開バージョン・ビルド番号、IPA の SHA-256、テスト結果と掲載 URL をリリースの記録へ残します。

問題が発生した場合は配信・公開設定を確認して対応し、修正版には新しいビルド番号を使用します。配信停止で、既に更新済みの利用者が旧版へ戻るとは扱いません。

## 注意

- ビルドスクリプトは成果物の作成まで、アップロードスクリプトは Apple 側の検証・送信までを行います。TestFlight のグループ設定、掲載情報の編集、審査提出、公開操作は別途行います。
- 旧資料ではアップロード用スクリプトの静的確認までを記録し、Apple 側の検証・アップロード・審査は未実施としています。本文書の作成でも送信は実行しておらず、現行版の受理・公開完了を示す記録ではありません。
