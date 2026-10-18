import Image from "next/image";
import DownloadSection from "./download-section";

const features = [
  {
    number: "01",
    name: "Diary",
    title: "日付ごとの日記",
    description: "日付を選んでテキストを入力し、端末内に保存できます。",
    icon: "/diary.png",
  },
  {
    number: "02",
    name: "Timer",
    title: "1〜180分のタイマー",
    description: "開始・一時停止・再開・リセットに対応します。MP3 / WAV の終了音を設定できます。",
    icon: "/timer.png",
  },
  {
    number: "03",
    name: "Password",
    title: "パスワード生成",
    description: "文字数と文字種を選んで生成し、コピーできます。乱数には OS の暗号学的乱数を使います。",
    icon: "/password.png",
  },
];

export default function Home() {
  return (
    <>
      <header className="site-header wrap">
        <a className="brand" href="#top" aria-label="Prelis トップへ">
          <Image src="/brand.png" alt="" width={38} height={38} priority />
          <span>prelis<span className="brand-dot">.</span></span>
        </a>
        <nav aria-label="メインナビゲーション">
          <a href="#features">機能</a>
          <a href="#download">入手方法</a>
        </nav>
      </header>

      <main id="top">
        <section className="hero wrap" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow">デスクトップ・モバイル・ウェブへ</p>
            <h1 id="hero-title">Prelis<span>マルチプラットフォームの<br />PoC アプリ</span></h1>
            <p className="lead">
              デスクトップ・Android・iOS・ウェブ版の対応状況と利用方法をご案内します。
            </p>
            <a className="button primary" href="#features">
              実装機能を見る <span aria-hidden="true">↘</span>
            </a>
          </div>

          <div className="hero-visual" aria-label="Prelis のデスクトップ画面を模した図。日記、タイマー、パスワードの3機能を選べます。">
            <div className="preview-window" aria-hidden="true">
              <div className="preview-sidebar">
                <div className="preview-brand"><Image src="/brand.png" alt="" width={24} height={24} /> prelis<span>.</span></div>
                <div className="preview-nav active"><Image src="/diary.png" alt="" width={17} height={17} /> Diary</div>
                <div className="preview-nav"><Image src="/timer.png" alt="" width={17} height={17} /> Timer</div>
                <div className="preview-nav"><Image src="/password.png" alt="" width={17} height={17} /> Password</div>
              </div>
              <div className="preview-content">
                <div className="preview-kicker">日記画面</div>
                <div className="preview-title">Diary<span>日記</span></div>
                <div className="preview-date">◀ &nbsp; 2026年10月17日 &nbsp; ▶</div>
                <div className="preview-editor">
                  <span>日記を入力</span>
                  <i /><i className="short" />
                </div>
                <div className="preview-save">保存する <span>↗</span></div>
              </div>
            </div>
            <div className="visual-caption">デスクトップ画面のイメージ</div>
          </div>
        </section>

        <section id="features" className="features section wrap" aria-labelledby="features-title">
          <div className="section-intro">
            <p className="eyebrow">機能一覧</p>
            <h2 id="features-title">実装している機能</h2>
          </div>
          <div className="feature-list">
            {features.map((feature) => (
              <article className="feature-row" key={feature.name}>
                <div className="feature-heading">
                  <span className="feature-number">{feature.number}</span>
                  <span className="feature-name"><Image src={feature.icon} alt="" width={29} height={29} /> {feature.name}</span>
                </div>
                <div>
                  <h3>{feature.title}</h3>
                  <p>{feature.description}</p>
                </div>
              </article>
            ))}
          </div>
        </section>

        <DownloadSection />
      </main>

      <footer className="site-footer wrap">
        <span>© 2026 Prelis</span>
        <span>マルチプラットフォームの PoC アプリ</span>
      </footer>
    </>
  );
}
