# モバイルのネイティブ実装

React Native 標準 API と Android・iOS の OS 標準 API を利用します。
ネイティブ機能のための追加ライブラリは導入していません。依存を追加する場合は、React Native 公式保守か、公式が案内する有力な基盤を優先して個別に判断します。コミュニティのディレクトリに掲載されていることだけを、公式保守の根拠にはしません。

## 配置と責務

| 対象 | TypeScript | Android / iOS |
| --- | --- | --- |
| アプリ全体 | `App.tsx` の Safe Area・ステータスバー | `MainApplication.kt`・`MainActivity.kt`、`AppDelegate.swift`・`SceneDelegate.swift` の起動処理、`PrelisPackage.kt` と Codegen のモジュール登録 |
| シェル | `src/shell/` の画面切り替え・戻る操作・離脱確認 | 現時点で独自モジュールは不要 |
| 日記 | `apps/diary/storage.ts` の日付検証・保存操作 | `apps/diary/` の `DiaryModule`・`DiaryStorage`。iOS の接続先は `DiaryService` |
| タイマー | `apps/timer/sound-storage.ts` の音声一覧・選択状態・更新手順 | `apps/timer/` の `TimerSoundModule`・`SoundStorage`・`SoundPicker`・`SoundPlayer`。iOS の接続先は `TimerSoundService` |
| パスワード | core の生成処理と `apps/password/` の画面状態 | `apps/password/` の `PasswordModule` が暗号学的乱数とコピーを提供。iOS の接続先は `PasswordService` |
| 共通基盤 | `src/shared/` の共通 UI | `shared/storage/` の `FileStorage`。Android の Promise エラー処理は `shared/native-promise.kt` |

TypeScript の機能別パスは `apps/mobile/src/` からの相対パスです。
Android のネイティブ機能別パスは `apps/mobile/android/app/src/main/java/com/prelismobile/`、iOS は `apps/mobile/ios/PrelisMobile/` からの相対パスです。

アプリ全体の起動クラスに個別機能の処理を置きません。各モジュールから OS 処理の担当クラスを呼び、複数機能で実際に使う処理だけを共通化します。乱数とコピーは現在 Password だけで使うため、Password に所属させています。Gradle モジュールや Xcode ターゲットは分割しません。

## TurboModule と Codegen

- `src/apps/diary/native/NativeDiary.ts` → `NativeDiary` / `DiaryModule`
- `src/apps/timer/native/NativeTimerSound.ts` → `NativeTimerSound` / `TimerSoundModule`
- `src/apps/password/native/NativePassword.ts` → `NativePassword` / `PasswordModule`

`package.json` の `codegenConfig` は `src/apps/` 配下を探索し、`PrelisMobileSpec` を生成します。`Native*.ts` のファイル名は Codegen が要求する規定名です。Android の実装は生成された Spec を継承し、iOS の実装は生成された protocol と JSI クラスを使用します。`NativeModules` の型アサーションや旧 `PrelisNative` を経由する互換窓口は設けません。

iOS の保存・乱数・コピー・取込み・再生・実行キューの処理は Swift です。`DiaryService`・`PasswordService`・`TimerSoundService` が React Native の Promise と各処理を接続します。Objective-C++ の `*-module.mm` と対応するヘッダーは、Codegen の C++ インターフェースと Swift をつなぐ最小限の呼出し転送に限定しています。通常の Objective-C `.m` 実装はありません。

この構成は [React Native 0.87 の Swift 導入手順](https://reactnative.dev/docs/0.87/the-new-architecture/turbo-modules-with-swift)に沿っています。フレームワークとの接続に必要な部分だけを Objective-C++ に残し、独自の互換 API は追加しません。Swift の起動処理も維持します。生成物は Git 管理せず、通常の Gradle ビルド・CocoaPods 準備で生成します。

## 保存と実行スレッド

- 保存先は従来どおり Android の `filesDir`、iOS の Application Support です。
- 日記は `diary/YYYY-MM-DD.txt`、音声一覧は `timer/sounds.json`、音声本体は `timer/sounds/<UUID>` を維持します。
- 音声一覧は `{version: 1, sounds: [{id, name, mimeType}], selectedId}` の JSON です。TypeScript で検証し、破損時はエラーにして上書きしません。
- 日記と音声一覧は、一時ファイルからの置換または OS のアトミック書込みで保存します。
- 音声は MP3・WAV を読み込み、実際の読込量を数えて 10 MiB 以下に制限します。空ファイル・失敗したコピーを削除します。
- 取込み後の一覧保存に失敗した場合は、取り込んだ音声ファイルを削除します。削除操作では一覧の保存に成功してからファイルを削除し、保存失敗で既存音声を失わないようにします。
- iOS のファイル処理は機能別のシリアルキューで実行します。Android の音声ファイル処理にも専用 executor を使います。選択画面・クリップボード・音声プレイヤーの操作はメインスレッドへ渡します。
- iOS で音声一覧が未作成の場合とファイル選択をキャンセルした場合は `NSNull` を返します。React Native の Promise は Swift の `nil` を JavaScript の `undefined` として扱うため、Spec の `null` と区別します。
- 乱数源は Android の `SecureRandom`、iOS の `arc4random_buf` です。計時は引き続き TypeScript が担当し、バックグラウンド通知や正確な時刻の音声再生は保証しません。

## 検証

通常の型チェック・lint・Jest・共有ロジックの検証はルートで `npm run check` を実行します。
音声一覧のテストでは旧保存形式の読込、破損データの拒否、取込みキャンセル、保存失敗時の取込みファイル削除、削除時の一覧保存失敗による既存ファイル保持、選択状態と再生停止を確認します。

Android は `npm run build:android:standalone` で JS・画像を同梱した動作確認用 APK を作成できます。ネイティブ API の登録、日記の保存・再読込、乱数生成・コピー、音声取込み・再生・削除を端末またはエミュレーターでも確認します。
iOS は `scripts/ios/build-ios-simulator.sh` が開発用 Mac へソースを同期してビルドします。Codegen の生成成功や Xcode 設定の正規化だけでは、iOS のネイティブコンパイル・操作確認の完了とは扱いません。

Mac 上で Simulator 用 Release アプリをビルドした後、`bash scripts/ios/test-native-on-mac.sh` で Apple 標準の XCTest を実行できます。検証専用の Simulator と一時 Xcode プロジェクトを生成し、終了時にその Simulator だけを削除します。既存の Simulator や製品の Xcode ターゲットには変更を加えません。
検証用の小さなアプリが WAV・空ファイルを Files に提供し、製品のファイル選択画面から取り込みます。テストのための分岐やダミー API を製品コードへ追加していません。ログ・`.xcresult`・要約は `apps/mobile/ios/build/native-smoke.*/` に保存します。

### この構成への移行時の確認結果

- 全 workspace の型チェック、モバイル lint、モバイル Jest 21 件、core・ウェブのテストを確認しました。
- Android の x86_64 向け standalone APK のビルドと、API 37 エミュレーターでの Metro を使わない起動を確認しました。
- Android で日記の保存・再読込、パスワード生成・コピー、WAV 取込み・試聴、プロセス再起動後の音声選択の保持を確認しました。
- Android で別画面へ移動した状態で実時間の 1 分タイマーを完了させ、OS のプレイヤー状態でループ再生を確認しました。リセットによるプレイヤー解放、音声削除後のプロセス再起動で選択が解除されることも確認しました。エミュレーターの音声出力は無効にしており、実際の音の聞こえ方は未確認です。
- iOS は Swift 移行後の Release ビルドが arm64・x86_64 の両方で成功しました。Codegen、共有 PNG 11 枚、AppIcon の同梱を確認し、取得したアプリ ZIP の整合性と SHA-256 も検証しました。
- iPhone 18 Pro / iOS 27.0 Simulator で XCTest 3 件（保存処理 2 件、製品 UI 操作 1 件）が成功しました。日記の保存・再起動後の再読込、パスワード生成・コピー、ファイル選択のキャンセル、空 WAV の拒否、WAV 取込み・試聴・選択状態の永続化を確認しました。
- iOS でも画面切り替えを含む実時間の 1 分タイマーを完了させ、終了音の再生エラーが出ないこと、リセットと音声削除、再起動後の選択解除を確認しました。保存処理では UTF-8、パスの検証、コピー内容、10 MiB 超過と空ファイルの拒否・失敗時の清掃も確認しました。無音 WAV を使ったため、実際の音の聞こえ方と実機での動作は未確認です。
- ローカルの取得成果物は `apps/mobile/ios/build/swift-simulator/` のアプリ ZIP、`verification.json`、`ios-simulator-artifacts.sha256`、`summary.json`、`test.log`、`swift-compile.log` です。ビルド成果物として Git 管理から除外されます。
- Mac の既存同期先には競合があったため、別の作業ディレクトリへ明示的に同期して検証しました。既存同期先の署名・配布用スクリプトなどは上書きしていません。
