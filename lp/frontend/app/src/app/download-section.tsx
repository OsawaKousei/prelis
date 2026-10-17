"use client";

import { useState } from "react";

type DownloadMethod = {
  name: string;
  description?: string;
  links?: { label: string; href: string }[];
};

type Platform = {
  name: string;
  requirements?: string;
  store: DownloadMethod;
  package: DownloadMethod;
};

const releases = "https://github.com/OsawaKousei/prelis/releases";
const readme = "https://github.com/OsawaKousei/prelis/blob/main/README.md#デスクトップ版のインストール";
const releaseNotes =
  "https://github.com/OsawaKousei/prelis/blob/main/dist/github-release/release-notes-v0.1.1.md#インストール方法";

const platforms: Platform[] = [
  {
    name: "Windows",
    requirements: "Windows 11（x64）",
    store: { name: "Microsoft Store" },
    package: {
      name: "NSIS / MSI",
      description: "GitHub Releases から setup.exe または .msi を入手してインストールします。",
      links: [
        { label: "リリースから入手する", href: releases },
        { label: "インストール手順", href: releaseNotes },
      ],
    },
  },
  {
    name: "macOS",
    store: { name: "App Store" },
    package: { name: "直接ダウンロード" },
  },
  {
    name: "Ubuntu",
    requirements: "Ubuntu（amd64）",
    store: {
      name: "Snap Store / APT",
      description: "Snap Store の stable チャンネル、または APT リポジトリからインストールできます。",
      links: [
        { label: "Snap Store で入手する", href: "https://snapcraft.io/prelis" },
        { label: "APT の設定・インストール手順", href: readme },
      ],
    },
    package: {
      name: "deb / AppImage",
      description: "GitHub Releases から .deb または .AppImage を入手します。署名の確認方法もご覧ください。",
      links: [
        { label: "リリースから入手する", href: releases },
        { label: "インストール手順と署名の確認", href: releaseNotes },
      ],
    },
  },
  {
    name: "Android",
    store: { name: "Google Play" },
    package: { name: "APK を直接入手" },
  },
  {
    name: "iOS",
    store: { name: "App Store" },
    package: { name: "直接ダウンロード" },
  },
];

function Method({ label, method }: { label: string; method: DownloadMethod }) {
  const available = Boolean(method.links?.length);

  return (
    <article className="download-method">
      <p className="download-method-label">{label}</p>
      <div className="download-method-heading">
        <h3>{method.name}</h3>
        <span className={available ? "download-status available" : "download-status"}>
          {available ? "利用可能" : "Coming soon"}
        </span>
      </div>
      {available && (
        <>
          <p className="download-method-description">{method.description}</p>
          <div className="download-links">
            {method.links?.map((link) => (
              <a href={link.href} key={link.label}>
                {link.label} <span aria-hidden="true">↗</span>
              </a>
            ))}
          </div>
        </>
      )}
    </article>
  );
}

export default function DownloadSection() {
  const [selected, setSelected] = useState(0);
  const platform = platforms[selected];

  return (
    <section id="download" className="download section wrap" aria-labelledby="download-title">
      <div className="section-intro">
        <p className="eyebrow">ダウンロード</p>
        <h2 id="download-title">アプリの入手方法</h2>
        <p className="download-intro">お使いの OS を選んで、入手方法をご確認ください。</p>
      </div>
      <div className="os-options" role="group" aria-label="OS を選択">
        {platforms.map((item, index) => (
          <button
            type="button"
            key={item.name}
            className={selected === index ? "os-option selected" : "os-option"}
            aria-pressed={selected === index}
            onClick={() => setSelected(index)}
          >
            {item.name}
          </button>
        ))}
      </div>
      <div className="download-result" aria-live="polite">
        <div className="download-platform-heading">
          <h3>{platform.name}</h3>
          {platform.requirements && <p>{platform.requirements}</p>}
        </div>
        <div className="download-methods">
          <Method label="ストアなどからインストール" method={platform.store} />
          <Method label="パッケージを直接入手" method={platform.package} />
        </div>
      </div>
    </section>
  );
}
