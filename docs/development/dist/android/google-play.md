# Google Play での頒布

署名・検証済みの AAB を Play Console へ提出し、テスト配信、製品版の審査・公開、配信後の確認を行う手順です。
コマンドは、特記がない限りリポジトリのルートで実行します。ビルド環境・鍵・バージョン更新・APK の直接頒布は [Android 配布物のビルド・署名](sign.md)を参照してください。
掲載文と画像の保存先は [Google Play 掲載素材](../../../../dist/play-store/README.md)です。

## 必要な環境と設定

- Play Console の対象アプリ `jp.co.kupacllc.prelis` を操作でき、テスト配信・製品版公開に必要な権限を持つアカウントを用意します。既存アプリを更新する場合は同じ登録を使用します。
- アカウントの本人確認・連絡先・契約など、Console のダッシュボードに出る未完了項目を解消します。アカウントに適用されるテスト要件・製品版へのアクセス条件も確認します。[アプリ作成と設定の公式手順](https://support.google.com/googleplay/android-developer/answer/9859152?hl=ja)を参照してください。
- [署名の準備](sign.md#署名の準備)と Release APK の動作確認を完了します。Play Console の登録証明書はローカルの署名検証だけでは確認できません。

| 項目 | このリポジトリの設定・提出物 |
| --- | --- |
| パッケージ名 | `jp.co.kupacllc.prelis` |
| ストア向け表示バージョン / ビルド番号 | 現行設定は `1.0.1` / `2`。提出履歴に続く番号を使用する |
| 提出用 AAB | `dist/android/v<version>/PrelisMobile_<version>_play.aab` |
| アップロード鍵 | 既定は `~/keys/play-upload.jks`、別名 `play-upload` |
| 直接頒布 APK のアプリ署名鍵 | 既定は `~/keys/app-signing.jks`、別名 `app-signing` |
| 掲載文・画像 | `dist/play-store/text.md` と同ディレクトリの画像 |

### Play アプリ署名を確認する

Play Console の「アプリの完全性」などのアプリ署名画面で、アップロード鍵とアプリ署名鍵を区別して確認します。
AAB はローカルのアップロード鍵で署名し、Google Play はアプリ署名鍵で生成 APK に署名して配信します。AAB の証明書と配信 APK の証明書を同じものとして比較しません。[Play アプリ署名の公式手順](https://developer.android.com/studio/publish/app-signing)を参照してください。

| 確認する証明書 | 照合先 |
| --- | --- |
| Console のアップロード鍵の証明書 | `play-upload.jks` と `PrelisMobile_<version>_play.aab` の SHA-256 |
| Console のアプリ署名鍵の証明書 | 既存の配信 APK。直接頒布との相互更新を提供する場合は `app-signing.jks` と `PrelisMobile_<version>_github.apk` の SHA-256 も照合 |

初回の Play アプリ署名設定で直接頒布と共通の鍵を使う場合は、Console の既存キーのエクスポート・アップロード手順に従い、アプリ署名鍵を登録します。鍵の転送には Console が案内する PEPK などの手順を使います。通常の AAB 提出ではキーストアやパスワードを添付しません。
既に登録済みの場合は登録内容を確認し、公開作業のたびに鍵を変更しません。Google 生成の鍵を使っている場合は、[更新互換性の制約](sign.md#play-と直接頒布の更新互換性)を確認します。

## 1. 提出する AAB を作成・確認する

```sh
npm run build:android:play
version="$(node -p 'require("./apps/mobile/app.json").expo.version')"
release_dir="dist/android/v${version}"
aab="${release_dir}/PrelisMobile_${version}_play.aab"
# 既定の鍵・別名の例。変更している場合は実際の値に置き換える
jarsigner -verify -strict -keystore "$HOME/keys/play-upload.jks" "$aab" play-upload
keytool -printcert -jarfile "$aab"
unzip -t "$aab"
(cd "$release_dir" && sha256sum -c SHA256SUMS)
```

直接頒布用 APK も同時に必要なら、ビルドコマンドを `npm run build:android:all` に置き換えます。ビルド元のコミットとタグ、公開バージョン・`versionCode`、AAB の SHA-256、アップロード証明書の SHA-256、動作確認の記録を残します。
前の AAB のビルド後にソースを変更した場合は、そのファイルを新しいソースの成果物として提出しません。

Release では R8 を有効にしています。調査用に `apps/mobile/android/app/build/outputs/mapping/release/mapping.txt` が生成された場合は、対応する AAB と一緒に保管します。ネイティブデバッグシンボルも生成・提出する場合は同じビルドのものを使います。次のビルドの `clean` で消える前に退避してください。ストアでの扱いは [リリース準備の公式手順](https://support.google.com/googleplay/android-developer/answer/9859348?hl=ja)を参照してください。

## 2. テストトラックへアップロードする

1. Play Console で対象アプリを開き、内部テストまたは対象のクローズドテストトラックを選び、リリースを作成します。
2. 確認した `PrelisMobile_<version>_play.aab` をアップロードします。リリース名と変更内容を入力し、Console が読み取ったパッケージ名・表示バージョン・`versionCode`・対象 SDK・対応端末を確認します。
3. アップロード証明書の不一致、使用済みの `versionCode`、API レベル・ネイティブライブラリの互換性などのエラーを解消します。警告は理由と影響を確認します。
4. テスターのアカウントやグループを登録し、テスト版を公開します。参加リンクと配信状況を確認します。

[対象 API レベルの公式要件](https://support.google.com/googleplay/android-developer/answer/11926878?hl=ja)を提出時に確認します。現行ビルド設定の target SDK は 36、compile SDK は 37 であり、提出要件で参照する対象 API は target SDK です。
ネイティブライブラリについては [16 KB ページサイズの公式手順](https://developer.android.com/guide/practices/page-sizes)と Console の診断も確認します。ローカル APK の ZIP アラインメント確認だけで、AAB から生成される配信 APK の適合を判定しません。

提出ファイルの選択から公開までの画面操作は [Google Play のリリース手順](https://support.google.com/googleplay/android-developer/answer/9859348?hl=ja)に従います。アップロード完了と、テスターへ配信可能な状態は区別します。

## 3. Google Play からインストールして確認する

テスターの Google アカウントで参加リンクを開き、Google Play から対象版をインストールします。手元の APK を `adb install` した確認では代替しません。
Metro を停止した状態で、[Release APK の確認項目](sign.md#3-android-でインストール起動を確認する)を配信版でも実施します。

- 新規インストール・起動と、端末のアプリ情報に表示される公開バージョンが提出した版に一致すること。
- 日記の保存・再読込、タイマー・音声、パスワード生成・コピーが動作すること。
- 360×640 dp の初期表示と、設定展開・キーボード表示後の操作に問題がないこと。
- 旧配信版から更新して起動できること。現行 Expo 版同士で保存データを継続利用できること。旧 CLI 版からの自動移行がない制約は別途記録・案内すること。
- 直接頒布との相互更新を案内する場合は、署名と `versionCode` の条件を満たす更新を実際に確認すること。

Console の事前公開レポートやクラッシュ情報を確認し、失敗があれば原因を解消して `versionCode` を増やした AAB を提出します。テスト後にコードを変更した場合は、新しい AAB を再テストします。製品版では、確認した同じ AAB をトラック間で昇格します。

## 4. 掲載情報を整えて製品版を審査に提出する

掲載素材は [dist/play-store/README.md](../../../../dist/play-store/README.md) と [text.md](../../../../dist/play-store/text.md)を基に準備します。保存済みの画像は過去の撮影物であり、現在のリング表示や折りたたみ構成を含む提出ビルドと一致するか確認し、必要な画像を撮り直します。

| 内容 | 確認すること |
| --- | --- |
| ストア掲載情報 | アプリ名、短い説明・詳しい説明、アイコン、フィーチャーグラフィック、スクリーンショット、カテゴリ、連絡先 |
| アプリのコンテンツ | 広告の有無、アプリへのアクセス方法、対象年齢・コンテンツ、コンテンツレーティングなど、Console の必須項目 |
| プライバシー・データセーフティ | 公開するプライバシーポリシー URL と、提出ビルド・依存 SDK の実際のデータの扱いに対応する申告 |
| 配信設定 | 国・地域、価格、対象端末、アカウントに適用されるテスト・製品版へのアクセス条件 |
| リリースノート | 変更内容、旧 CLI 版からのデータ自動移行がないこと、タイマーのバックグラウンド動作などの制約 |

端末内に保存する日記・取込音声、生成パスワードのコピー、Manifest のバックアップ設定、依存 SDK やネットワーク通信を確認して申告内容を決めます。端末内保存という説明だけで「収集なし」を確定せず、[データセーフティの公式手順](https://support.google.com/googleplay/android-developer/answer/10787469?hl=ja)に沿って回答します。プライバシーポリシーや連絡先の URL は実際に公開・到達できるものを設定します。

テスト済み AAB を製品版トラックのリリースに選択し、リリース内容と未完了項目を確認して審査へ送信します。審査・公開タイミングは Console の公開管理設定に従います。更新時に段階的公開を選ぶ場合は、対象割合を確認して開始します。
新規公開か更新か、管理対象の公開を使うかによって操作と公開時点が異なるため、最終確認画面で対象トラック・版・国と地域・公開タイミングを確認します。[リリース準備・公開の公式手順](https://support.google.com/googleplay/android-developer/answer/9859348?hl=ja)を参照してください。

## 5. 公開した版を確認する

1. Console で審査・公開状況と対象版を確認し、一般利用者向けの [Google Play 掲載ページ](https://play.google.com/store/apps/details?id=jp.co.kupacllc.prelis)から掲載文・画像・配信対象を確認します。
2. 対象地域・端末の Google Play から新規インストールと旧版からの更新を確認します。段階的公開中は配信対象に含まれるアカウント・端末で確認します。
3. 起動・主要操作・クラッシュ / ANR の状況を確認し、公開日時、公開バージョン・`versionCode`、AAB の SHA-256、テスト結果と掲載 URL をリリースの記録へ残します。

問題が発生した場合は Console の公開停止・段階的公開の停止などを検討し、修正は新しい `versionCode` の AAB で行います。停止操作で既に更新済みの利用者が旧版へ戻るとは扱いません。

## 注意

- `npm run build:android:play` / `build:android:all` は署名付き成果物の作成までを行います。アップロード・審査提出・公開はこのスクリプトに含まれません。
- AAB の署名検証成功は、Google Play のポリシー適合や端末上の動作確認を保証しません。Console のチェックとテスト配信を経て公開します。
- この文書は作業手順であり、現行版のストア提出・審査通過・公開完了を示す記録ではありません。
