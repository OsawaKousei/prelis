import Image from "next/image";

const features = [
  {
    number: "01",
    name: "Diary",
    title: "今日のことを、今日の日付に。",
    description: "日付を選んで、思ったことをそのまま記録。書いた内容は端末内に保存され、あとから同じ日付で読み返せます。",
    icon: "/diary.png",
  },
  {
    number: "02",
    name: "Timer",
    title: "集中する時間を、見える形に。",
    description: "1〜180分から時間を決めてスタート。一時停止や再開もすぐにでき、終了音には手持ちの音声を設定できます。",
    icon: "/timer.png",
  },
  {
    number: "03",
    name: "Password",
    title: "必要なときに、すばやく生成。",
    description: "長さと文字種を選ぶだけ。端末の暗号学的乱数を使ってパスワードを生成し、ボタンでコピーできます。",
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
          <a href="#features">できること</a>
          <a href="#platforms">利用環境</a>
        </nav>
      </header>

      <main id="top">
        <section className="hero wrap" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow">CLEAR / LIGHT / SPEED</p>
            <h1 id="hero-title">日々を、<br /><span>軽やかに整える。</span></h1>
            <p className="lead">
              書く、時間を計る、パスワードをつくる。<br />
              毎日の小さな作業を、ひとつの場所で迷わず進めるアプリです。
            </p>
            <a className="button primary" href="#features">
              3つの機能を見る <span aria-hidden="true">↘</span>
            </a>
            <p className="hero-note">デスクトップ / Android 向けに開発中</p>
          </div>

          <div className="hero-visual" aria-label="Prelis の画面イメージ。日記、タイマー、パスワードの3機能を選べます。">
            <div className="preview-window" aria-hidden="true">
              <div className="preview-sidebar">
                <div className="preview-brand"><Image src="/brand.png" alt="" width={24} height={24} /> prelis<span>.</span></div>
                <div className="preview-nav active"><Image src="/diary.png" alt="" width={17} height={17} /> Diary</div>
                <div className="preview-nav"><Image src="/timer.png" alt="" width={17} height={17} /> Timer</div>
                <div className="preview-nav"><Image src="/password.png" alt="" width={17} height={17} /> Password</div>
              </div>
              <div className="preview-content">
                <div className="preview-kicker">DAILY SPACE</div>
                <div className="preview-title">Diary<span>今日の記録</span></div>
                <div className="preview-date">◀ &nbsp; 2026年10月17日 &nbsp; ▶</div>
                <div className="preview-editor">
                  <span>今日のメモを、ここから。</span>
                  <i /><i className="short" />
                </div>
                <div className="preview-save">保存する <span>↗</span></div>
              </div>
            </div>
            <div className="visual-caption">A clear space for your everyday.</div>
          </div>
        </section>

        <section id="features" className="features section wrap" aria-labelledby="features-title">
          <div className="section-intro">
            <p className="eyebrow">THREE ESSENTIAL TOOLS</p>
            <h2 id="features-title">使いたい機能へ、すぐに。</h2>
            <p>日常の作業に必要な機能を、すっきりとまとめました。</p>
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

        <section id="platforms" className="platforms section" aria-labelledby="platforms-title">
          <div className="wrap platforms-inner">
            <div>
              <p className="eyebrow">DESKTOP & ANDROID</p>
              <h2 id="platforms-title">いつもの端末で、<br />自分のペースで。</h2>
            </div>
            <div className="platform-copy">
              <p>Prelis はデスクトップと Android で、同じ3つの機能を提供します。それぞれの画面に合った操作で、必要なことに集中できます。</p>
              <p className="platform-note">日記のデータは端末ごとに保存されます。端末間の同期機能はありません。</p>
            </div>
          </div>
        </section>

        <section className="closing wrap" aria-labelledby="closing-title">
          <p className="eyebrow">PRELIS</p>
          <h2 id="closing-title">毎日を、もっと明快に。</h2>
          <a className="text-link" href="#top">ページの先頭へ戻る <span aria-hidden="true">↑</span></a>
        </section>
      </main>

      <footer className="site-footer wrap">
        <span>© 2026 Prelis</span>
        <span>Clear interfaces. Light structures. Fluid motion.</span>
      </footer>
    </>
  );
}
