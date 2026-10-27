import Link from "next/link";
import type { Metadata } from "next";
import Image from "next/image";

export const metadata: Metadata = {
  title: "プライバシーポリシー | Prelis",
  description: "Prelis・Prelis Mobileの全プラットフォーム共通プライバシーポリシー。データの取り扱い、端末内データの削除方法、お問い合わせ窓口をご案内します。",
  alternates: { canonical: "https://prelis.prj.kupac.co.jp/privacy/" },
};

const sections = [
  { id: "scope", title: "適用範囲" },
  { id: "data", title: "データの収集・使用と端末内保存" },
  { id: "sharing", title: "第三者への共有・広告・解析" },
  { id: "deletion", title: "保存期間と削除方法" },
  { id: "platforms", title: "ウェブ版・外部サービスについて" },
  { id: "inquiries", title: "お問い合わせ時に提供される情報" },
  { id: "security", title: "情報の安全管理" },
  { id: "changes", title: "ポリシーの変更" },
  { id: "contact", title: "開発者・お問い合わせ窓口" },
  { id: "history", title: "改訂履歴" },
];

export default function PrivacyPage() {
  return (
    <>
      <header className="site-header wrap">
        <Link className="brand" href="https://prelis.prj.kupac.co.jp/" aria-label="Prelis トップへ">
          <Image src="/brand.png" alt="" width={38} height={38} priority />
          <span>prelis<span className="brand-dot">.</span></span>
        </Link>
        <nav aria-label="メインナビゲーション"><Link href="https://prelis.prj.kupac.co.jp/">トップへ戻る <span aria-hidden="true">↗</span></Link></nav>
      </header>
      <main id="top" className="privacy-page wrap">
        <div className="privacy-heading">
          <p className="eyebrow">PRIVACY POLICY</p>
          <h1>プライバシーポリシー</h1>
          <p className="privacy-subtitle">Prelis / Prelis Mobile ― 全プラットフォーム共通</p>
          <p className="privacy-dates">制定日：<time dateTime="2026-10-12">2026年10月12日</time><br />最終改定日：<time dateTime="2026-10-27">2026年10月27日</time></p>
          <p>合同会社KUPAC（KUPAC LLC、以下「当社」といいます。）は、当社が提供する「Prelis」および「Prelis Mobile」（以下、総称して「本アプリ」といいます。）におけるユーザーのプライバシーを尊重し、ユーザーデータを以下のとおり取り扱います。</p>
        </div>
        <div className="privacy-layout">
          <nav className="privacy-toc" aria-label="プライバシーポリシーの目次">
            <p>目次</p>
            <ol>{sections.map((section) => <li key={section.id}><a href={`#${section.id}`}>{section.title}</a></li>)}</ol>
          </nav>
          <article className="privacy-content" aria-label="ポリシー本文">
            <section id="scope" aria-labelledby="scope-title">
              <h2 id="scope-title">1. 適用範囲</h2>
              <p>本ポリシーは、本アプリのデスクトップ版（Windows・macOS・Linux／Ubuntu）、モバイル版（Android・iOS）およびウェブ版に共通して適用されます。Google Play等のアプリストアから入手した場合と、当社が提供するパッケージを直接入手した場合のいずれも対象です。開発中の版についても、当社が提供する範囲で適用されます。</p>
              <p>本ポリシーは、当社の他のアプリや、本アプリ以外のサービスには適用されません。アプリの対応環境・配信状況は、<Link href="https://prelis.prj.kupac.co.jp/#download">入手方法のご案内</Link>をご確認ください。本ポリシーの対象に含まれることは、各環境・地域での配信を意味するものではありません。</p>
              <p>本ポリシーは日本語で提供します。本ページの閲覧には、ログインや居住地域による制限を設けません。</p>
            </section>
            <section id="data" aria-labelledby="data-title">
              <h2 id="data-title">2. データの収集・使用と端末内保存</h2>
              <p>本アプリは、アプリ内に入力・保存されたデータ、個人情報、機密情報、端末情報および利用状況に関するデータを、当社が取得する目的で収集せず、当社や第三者のサーバーへ送信しません。氏名、メールアドレス、位置情報、連絡先、広告ID、利用履歴などを収集することはありません。アカウントの作成・ログイン機能はありません。</p>
              <p>日記の内容やアプリの設定など、機能の提供に必要なデータは、ユーザーの端末内（ウェブ版ではブラウザ内の保存領域）で取り扱います。当社がこれらの内容を閲覧・取得することはありません。端末内にデータを保存することと、当社がサーバーへ収集することは区別されます。</p>
              <p>ウェブ版の配信に伴う通信や、OS・アプリストア等が独自に行う情報の取り扱いについては、第5項をご確認ください。</p>
            </section>
            <section id="sharing" aria-labelledby="sharing-title">
              <h2 id="sharing-title">3. 第三者への共有・広告・解析</h2>
              <p>本アプリから、広告配信事業者、アクセス解析事業者、クラウドサービス事業者その他の第三者へ、アプリ内のユーザーデータを送信・共有することはありません。ユーザーデータを収集・送信する広告SDKや解析SDKは使用しません。当社は、本アプリのユーザーの個人情報や機密情報を販売しません。</p>
            </section>
            <section id="deletion" aria-labelledby="deletion-title">
              <h2 id="deletion-title">4. 保存期間と削除方法</h2>
              <p>当社は、本アプリを通じてアプリ内のユーザーデータを収集しないため、当社のサーバーに保存される当該データはなく、その保存期間もありません。削除するアプリのアカウントもありません。</p>
              <p>端末内のデータは、ユーザーが削除するか、OS・ブラウザ等の機能により消去されるまで保存されます。設定等を含む保存データを削除する場合は、ご利用の環境に応じて以下の方法をご確認ください。</p>
              <dl className="privacy-platforms">
                <div><dt>Android</dt><dd>Androidの設定画面から、本アプリのストレージ・データを消去するか、本アプリをアンインストールしてください。</dd></div>
                <div><dt>iOS / iPadOS</dt><dd>OSの設定画面等から本アプリを削除してください。「Appを取り除く」操作ではデータが残る場合があるため、データの削除には「Appを削除」を選択してください。</dd></div>
                <div><dt>Windows / macOS / Linux</dt><dd>本アプリをアンインストールし、必要に応じて本アプリのデータ保存フォルダーも削除してください。アンインストールだけではデータが残る場合があります。保存場所が不明な場合は、お問い合わせ窓口へご連絡ください。</dd></div>
                <div><dt>ウェブブラウザ</dt><dd>ブラウザの設定から、ウェブ版を利用したサイトのサイトデータ・ローカルストレージ等を削除してください。閲覧履歴やキャッシュの削除だけでは、保存データが残る場合があります。</dd></div>
              </dl>
              <p>操作方法は、端末、OS、ブラウザのバージョンにより異なります。削除したデータを当社が復元することはできません。端末やOS等のバックアップに含まれるデータは、各サービスの設定・手順に従って削除してください。お問い合わせ情報の保存・削除については、第6項に定めます。</p>
            </section>
            <section id="platforms" aria-labelledby="platforms-title">
              <h2 id="platforms-title">5. ウェブ版・外部サービスについて</h2>
              <p>ウェブ版や本アプリの案内サイトを閲覧する際は、ページや必要なファイルを配信するため、ブラウザと配信サーバーの間で通信が発生します。この通信に伴い、配信基盤においてIPアドレス、アクセス日時、ブラウザ情報等の技術的な情報が処理・記録される場合があります。これは、第2項に記載した日記等のアプリ内データの送信とは異なります。</p>
              <p>アプリの入手、外部リンクの閲覧、OS・ブラウザの診断機能やバックアップ機能等の利用に伴い、アプリストア、配布サイト、OS・ブラウザの提供元等が独自に情報を取り扱う場合があります。それぞれのサービスによる情報の取り扱いには、各提供元のプライバシーポリシーが適用されます。</p>
            </section>
            <section id="inquiries" aria-labelledby="inquiries-title">
              <h2 id="inquiries-title">6. お問い合わせ時に提供される情報</h2>
              <p>本アプリからの自動的なデータ収集とは別に、ユーザーが当社へメールでお問い合わせを行った場合、当社は、送信元のメールアドレス、氏名（記載された場合）、お問い合わせ内容および任意の添付情報を受け取ります。これらの情報は、お問い合わせへの回答、必要な調査および対応のためにのみ使用します。</p>
              <p>メールの配信・保管などに必要な範囲で、メールサービス事業者に情報の取り扱いを委託します。本人の同意がある場合または法令により認められる場合を除き、その他の第三者へ個人データを提供しません。お問い合わせ情報を広告配信に利用したり販売したりすることはありません。</p>
              <p>お問い合わせ情報は、対応および関連する問題の解決に必要な期間保存し、不要になった後に削除します。法令上の保存義務や紛争対応のために保存が必要な場合は、その必要な期間に限り保存します。</p>
              <p>お問い合わせ情報の開示・訂正・削除・利用停止等を希望する場合は、下記窓口へご連絡ください。必要な本人確認を行ったうえで法令に従って対応します。削除できない情報がある場合は、その理由をお知らせします。</p>
            </section>
            <section id="security" aria-labelledby="security-title">
              <h2 id="security-title">7. 情報の安全管理</h2>
              <p>本アプリは、アプリ内のユーザーデータを当社や第三者のサーバーへ送信・保管しません。お問い合わせにより当社が受け取った情報については、アクセス権限の制限、認証情報の管理、通信の保護および委託先の監督など、漏えい、滅失、毀損、不正アクセスを防止するために必要な措置を講じます。</p>
            </section>
            <section id="changes" aria-labelledby="changes-title">
              <h2 id="changes-title">8. ポリシーの変更</h2>
              <p>本アプリの機能や情報の取り扱いを変更する場合は、変更内容と施行日を本ページの「改訂履歴」でお知らせします。</p>
              <p>今後、本アプリにデータ収集やアカウント機能を追加する場合は、収集するデータ、利用目的、共有先、保存期間および削除方法を事前に本ポリシーへ反映し、必要なアプリ内での説明と同意の取得を行います。</p>
            </section>
            <section id="contact" aria-labelledby="contact-title">
              <h2 id="contact-title">9. 開発者・お問い合わせ窓口</h2>
              <p>開発者：合同会社KUPAC（KUPAC LLC）<br />対象アプリ：Prelis / Prelis Mobile</p>
              <p>本アプリのプライバシーやお問い合わせ情報の取り扱いについては、以下の窓口へご連絡ください。件名または本文に「Prelis」または「Prelis Mobile」、ご利用のプラットフォームおよびご用件をご記載ください。</p>
              <div className="privacy-contact"><p>合同会社KUPAC 個人情報お問い合わせ窓口</p><a href="mailto:contact@kupac.co.jp">contact@kupac.co.jp <span aria-hidden="true">↗</span></a></div>
            </section>
            <section id="history" aria-labelledby="history-title">
              <h2 id="history-title">10. 改訂履歴</h2>
              <dl className="privacy-platforms">
                <div>
                  <dt><time dateTime="2026-10-27">2026年10月27日 改訂・施行</time></dt>
                  <dd>Google Play向けポリシーを全プラットフォーム共通の内容へ統合。端末・ブラウザ内のデータ削除方法およびウェブ版・外部サービスの取り扱いを追記。</dd>
                </div>
                <div>
                  <dt><time dateTime="2026-10-12">2026年10月12日 制定</time></dt>
                  <dd>Prelis MobileのGoogle Play向けプライバシーポリシーを制定。</dd>
                </div>
              </dl>
            </section>
            <a className="privacy-back" href="#top">ページの先頭へ ↑</a>
          </article>
        </div>
      </main>
      <footer className="site-footer wrap"><span>© 2026 Prelis</span><Link href="https://prelis.prj.kupac.co.jp/">Prelis トップへ</Link></footer>
    </>
  );
}
