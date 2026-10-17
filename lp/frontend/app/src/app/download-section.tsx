"use client";

import { useState } from "react";

type DownloadMethod = {
  label: string;
  name: string;
  description?: string;
  links?: { label: string; href: string }[];
};

type Platform = {
  name: string;
  requirements?: string;
  methods: DownloadMethod[];
  note?: string;
};

const releases = "https://github.com/OsawaKousei/prelis/releases";
const readme = "https://github.com/OsawaKousei/prelis/blob/main/README.md#デスクトップ版のインストール";
const releaseNotesFile = "https://github.com/OsawaKousei/prelis/blob/main/dist/github-release/release-notes-v0.1.1.md";
const releaseNotes = `${releaseNotesFile}#インストール方法`;
const androidReleaseNotes = `${releaseNotesFile}#android-apk`;

const platforms: Platform[] = [
  {
    name: "Windows",
    requirements: "Windows 11（x64）",
    methods: [
      { label: "ストアなどからインストール", name: "Microsoft Store" },
      {
        label: "パッケージを直接入手",
        name: "NSIS / MSI",
        description: "GitHub Releases から setup.exe または .msi を入手してインストールします。",
        links: [
          { label: "リリースから入手する", href: releases },
          { label: "インストール手順", href: releaseNotes },
        ],
      },
    ],
  },
  {
    name: "macOS",
    methods: [
      { label: "ストアなどからインストール", name: "App Store" },
      { label: "パッケージを直接入手", name: "直接ダウンロード" },
    ],
  },
  {
    name: "Ubuntu",
    requirements: "Ubuntu（amd64）",
    methods: [
      {
        label: "ストアなどからインストール",
        name: "Snap Store / APT",
        description: "Snap Store の stable チャンネル、または APT リポジトリからインストールできます。",
        links: [
          { label: "Snap Store で入手する", href: "https://snapcraft.io/prelis" },
          { label: "APT の設定・インストール手順", href: readme },
        ],
      },
      {
        label: "パッケージを直接入手",
        name: "deb / AppImage",
        description: "GitHub Releases から .deb または .AppImage を入手します。署名の確認方法もご覧ください。",
        links: [
          { label: "リリースから入手する", href: releases },
          { label: "インストール手順と署名の確認", href: releaseNotes },
        ],
      },
    ],
  },
  {
    name: "Android",
    requirements: "Android 7.0 以降",
    methods: [
      { label: "ストアなどからインストール", name: "Google Play" },
      {
        label: "パッケージを直接入手",
        name: "APK",
        description: "GitHub Releases から APK を入手します。インストール手順と SHA-256 の確認方法もご覧ください。",
        links: [
          { label: "リリースから入手する", href: `${releases}/tag/v0.1.1` },
          { label: "インストール手順とハッシュの確認", href: androidReleaseNotes },
        ],
      },
    ],
  },
  {
    name: "iOS",
    methods: [
      { label: "ストアなどからインストール", name: "App Store" },
      { label: "パッケージを直接入手", name: "直接ダウンロード" },
    ],
  },
  {
    name: "Web",
    methods: [
      {
        label: "ブラウザーで利用",
        name: "ウェブ版",
        description: "ブラウザーから開いて利用できます。",
        links: [{ label: "ウェブ版を開く", href: "https://app-prelis.prj.kupac.co.jp/" }],
      },
    ],
    note: "ブラウザーの制約により、一部の機能や動作が異なり、利用できない場合があります。",
  },
];

function Method({ method }: { method: DownloadMethod }) {
  const available = Boolean(method.links?.length);

  return (
    <article className="download-method">
      <p className="download-method-label">{method.label}</p>
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
        <p className="eyebrow">利用方法</p>
        <h2 id="download-title">アプリの利用方法</h2>
        <p className="download-intro">お使いの環境を選んで、利用方法をご確認ください。</p>
      </div>
      <div className="os-options" role="group" aria-label="利用環境を選択">
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
        <div className={platform.methods.length === 1 ? "download-methods single" : "download-methods"}>
          {platform.methods.map((method) => <Method method={method} key={method.label} />)}
        </div>
        {platform.note && <p className="download-note">{platform.note}</p>}
      </div>
    </section>
  );
}
