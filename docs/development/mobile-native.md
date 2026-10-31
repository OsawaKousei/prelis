# モバイルの Expo 構成

`apps/mobile/` は Expo SDK 58 / React Native 0.88 の Android・iOS アプリです。旧実装は `apps/mobile-old/` に隔離し、npm workspace、通常のチェックとビルド、Mac 同期の対象から外しています。

## 配置と責務

| 対象 | 配置・利用する仕組み |
| --- | --- |
| 起動・画面遷移 | `src/app/_layout.tsx` の Expo Router Tabs・StatusBar・SafeAreaProvider |
| ホーム | `src/app/index.tsx` |
| 日記 | `src/apps/diary/` の画面・日付検証・Expo SQLite KV 保存 |
| タイマー | `src/apps/timer/` の TimerProvider・画面・音声一覧の更新手順 |
| パスワード | `src/apps/password/` の画面、core の生成処理、Expo Crypto・Clipboard |
| 共通 UI | `src/shared/` の色・ボタン・共有 PNG |
| ネイティブプロジェクト | Expo 標準の起動クラス・モジュール登録と、手動管理する署名設定 |

`src/app/` には経路とレイアウトだけを置き、個別機能の処理は `src/apps/` に置きます。タイマーの状態とプレイヤーはルートの Provider に置き、画面のマウント状態に依存させません。

## 公式モジュール

- `expo-router`：ホーム・Diary・Timer・Password のタブ遷移。
- `expo-sqlite/kv-store`：日記本文と音声一覧・選択状態の永続化。
- `expo-document-picker`：OS のファイル選択画面。
- `expo-file-system`：選択した音声のサイズ確認、Documents へのコピー、削除。
- `expo-audio`：試聴・終了音のループ再生・停止・音声セッション。
- `expo-crypto`：パスワード用の暗号学的乱数と音声 UUID。
- `expo-clipboard`：コピー。Android のパスワードは sensitive として設定。
- `expo-status-bar`・`expo-system-ui`：OS の表示設定。

現在の機能に独自の Swift・Kotlin モジュール、Objective-C++ 接続、Codegen Spec は不要です。今後も Expo が提供する機能で実現できる場合は、多少の仕様変更を許容して公式モジュールを優先します。

## 保存と仕様変更

日記は SQLite の `diary:YYYY-MM-DD`、音声一覧は `timer:sounds` に保存します。SQLite の単一キー更新を使い、自作のアトミックファイル置換は行いません。旧 TXT・JSON の読込みや自動移行は提供しません。

音声本体は `Paths.document/timer/sounds/<UUID>.mp3|wav` に保存します。DocumentPicker がキャッシュへコピーした後に実ファイルの存在・サイズ・拡張子を検証し、空ファイルと 10 MiB 超過を拒否します。取込み完了・失敗のいずれでも選択時のキャッシュを清掃します。選択画面内部でサイズ検証前に一時コピーされることは許容します。

取込みは音声をコピーしてから一覧を保存し、一覧保存の失敗時は追加ファイルを清掃します。削除は一覧保存の成功後に音声本体を削除します。壊れた一覧はエラーとし、自動的に上書きしません。

日記の下書きはタブを切り替えても保持します。別の日付へ変更する時は未保存内容の破棄を確認します。計時は TypeScript が期限との差を計算し、バックグラウンド中の正確な終了音は保証しません。マイク・バックグラウンド録音・バックグラウンド再生の機能は追加しません。

詳細は [v0.1.3 仕様書](../specs/v0.1.3.md) を参照してください。

## 依存関係とビルド

`npm ci` はリポジトリのルートで実行します。デスクトップ・ウェブは React 19.2.3、モバイルは SDK 58 に合わせた React 19.3 を使用します。モバイル向け React・React Native はルートの開発依存にも SDK 対応版を明示し、Expo パッケージやテスト基盤が旧版を解決しないようにします。React 全体の override は設けません。ネイティブプロジェクトは直接管理するため、Expo Doctor の appConfigFieldsNotSyncedCheck だけを無効にし、設定変更を手動で同期します。

開発はルートの `npm run start:mobile`・`npm run android`・`npm run ios` から Expo CLI を呼び出します。依存追加は `apps/mobile/` で `npx expo install` を使います。Android・iOS のみを対象とし、ウェブは既存の `apps/web/` で開発します。

署名付き配布は既存の `scripts/android/`・`scripts/ios/` を維持します。Android は Play 用と直接配布用の別々の keystore、iOS は既存の Apple 証明書・Provisioning Profile を使います。Expo アカウント・EAS・鍵のクラウド登録は使いません。

Android の署名スクリプトは Gradle の `clean` に先立ち、アプリの `.cxx` と `build/intermediates/cxx` を削除します。依存モジュールの Codegen 出力が清掃された後に、古いアプリの CMake 設定がその出力を参照して `clean` が失敗する問題を回避します。署名設定や配布形式は変更しません。

`ios/`・`android/` を Git 管理し、Podfile.lock と Xcode 設定も管理します。通常のビルドでは `expo prebuild --clean` を実行しません。再生成が必要な場合は手動の署名設定も復元して差分を検証します。

Mac 同期では、新しい依存・Router の経路・公式モジュールを送ります。Xcode で生成されるファイルやキャッシュは同期しません。既存同期先に競合がある場合は上書きせず、別の作業ディレクトリで検証します。

## 検証

- `npm run check`：全 workspace の型チェック、Expo lint、モバイル Jest、core・ウェブのテスト。
- `cd apps/mobile && npx expo install --check`：SDK と依存の整合性。
- `cd apps/mobile && npx expo export --platform all`：Android・iOS の Hermes バンドルと共有画像。
- `npm run build:android:standalone`：JS を同梱した検証用 APK。署名はデバッグ鍵。
- `npm run build:android:all`：既存の別々の鍵で署名した AAB・APK。
- `bash scripts/ios/build-ios-simulator.sh`：Mac 同期・CocoaPods・Simulator 向け Release ビルド・成果物取得。
- `bash scripts/ios/build-all.sh`：既存の証明書による archive・IPA export と検証。
- Mac で `bash scripts/ios/test-native-on-mac.sh`：製品アプリの XCTest 操作検証。専用 Simulator を作成し、終了時にその端末だけを削除。

Jest では、保存失敗時のデータ保持、日付変更で破棄した下書きが読込失敗時に残らないこと、音声サイズの境界・キャンセル・破損一覧・清掃、Router をまたぐ日記とタイマーの状態、音声準備中のリセット、乱数生成・コピーを検証します。XCTest の小さな補助アプリは Files に WAV を提供するための検証専用コードであり、製品の独自ネイティブモジュールではありません。

### 今回の検証結果

- ルートの `npm ci` と `npm run check` が成功。全 workspace の型チェック、警告なしの Expo lint、モバイル Jest 23 件、core・ウェブの既存テストが通りました。
- Expo Doctor は 19/19 項目が成功。React・React DOM 19.3.0 と React Native 0.88.1 は、ルートとモバイルで同じ実体を解決することを確認しました。`expo install --check` も対応版と判定しました。
- 最終ソースの `expo export --platform all` が成功。Android・iOS の Hermes バンドルと共有画像を出力しました。ルートの依存変更後もデスクトップ・ウェブの Vite ビルドは成功しました。
- Android の standalone APK と、既存の別々の鍵で署名した Play 用 AAB・直接配布用 APK を生成し、署名を検証しました。最終 APK の application ID は `jp.co.kupacllc.prelis`、versionName は `0.1.3`、versionCode は `1` です。
- Android API 37 の専用エミュレーターで、最終署名付き APK を Metro なしで起動しました。日記の下書き保持・保存・再起動後の再読込、パスワード生成・コピー、WAV 取込み・試聴・選択保持、別タブでの実時間 1 分の計時・完了、リセット・削除・再起動後の削除保持を確認しました。
- Xcode 27.1 で Universal Simulator Release（arm64・x86_64）、実機向け archive（arm64）、既存の Apple Distribution 証明書・App Store 用プロファイルによる IPA export が成功しました。ID・バージョン・署名・同梱 JS・共有画像 11 点とアプリアイコンを検証し、取得した成果物の SHA-256 も一致しました。
- 最終 Simulator アプリを iOS 27.0 の専用 iPhone 18 Pro で XCTest 操作検証し、1 件の総合シナリオが成功しました。日記の再読込、パスワード生成・コピー、Picker のキャンセル・空 WAV 拒否・正常 WAV 取込み・試聴・選択保持、タブをまたぐ実時間 1 分の計時・完了、リセット・削除の永続化を確認しました。

Android 成果物は `dist/android/`、取得した iOS 成果物・検証レポート・ログは `apps/mobile/ios/build/expo/` に置きます（いずれも Git 管理対象外）。iOS は既存同期先に競合があったため、Mac の `/Users/kousei/prelis-expo-check.I7Dqxr9k` で検証し、既存の同期先は上書きしていません。専用 Simulator はテスト後に削除し、既存の Simulator は維持しました。

実機での聴音、Bluetooth・着信による割込み、バックグラウンド中の音声動作、ストアへのアップロードは未確認です。操作検証には無音 WAV を使用し、再生要求とエラーがないことを確認しました。バックグラウンド中の正確な終了音は仕様として保証しません。
