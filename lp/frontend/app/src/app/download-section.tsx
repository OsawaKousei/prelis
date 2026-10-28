"use client";

import { useState } from "react";

type DownloadMethod = {
  label: string;
  name: string;
  description?: string;
  links?: { label: string; href: string }[];
  developmentStatus?: "開発用" | "開発中";
};

type Platform = {
  name: string;
  requirements?: string;
  methods: DownloadMethod[];
  note?: string;
  warning?: boolean;
};

const releases = "https://github.com/OsawaKousei/prelis/releases";
const microsoftStore = "https://apps.microsoft.com/detail/xp99h4k206pvbv?hl=ja-JP&gl=JP";
const release = `${releases}/tag/v0.1.1`;
const readme = "https://github.com/OsawaKousei/prelis/blob/main/README.md#デスクトップ版のインストール";
const releaseNotesFile = "https://github.com/OsawaKousei/prelis/blob/main/dist/github-release/release-notes-v0.1.1.md";
const releaseNotes = `${releaseNotesFile}#インストール方法`;
const androidReleaseNotes = `${releaseNotesFile}#android-apk`;

const platforms: Platform[] = [
  {
    name: "Windows",
    requirements: "Windows 11（x64）",
    methods: [
      {
        label: "ストアなどからインストール",
        name: "Microsoft Store",
        description: "Microsoft Store から Windows 版をインストールできます。",
        links: [{ label: "Microsoft Store で入手する", href: microsoftStore }],
      },
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
    requirements: "Apple Silicon（arm64）",
    methods: [
      { label: "ストアなどからインストール", name: "App Store" },
      {
        label: "パッケージを直接入手",
        name: "DMG / .app ZIP",
        developmentStatus: "開発用",
        description: "GitHub Release に添付された場合に入手できる開発用パッケージです。Apple の署名・公証はなく、macOS で起動を止められる場合があります。",
        links: [
          { label: "GitHub Release を確認", href: release },
          { label: "パッケージと注意事項", href: releaseNotesFile },
        ],
      },
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
      {
        label: "ストアなどからインストール",
        name: "Google Play",
        description: "Google Play から Android 版をインストールできます。",
        links: [
          { label: "Google Play で入手する", href: "https://play.google.com/store/apps/details?id=jp.co.kupacllc.prelis" },
        ],
      },
      {
        label: "パッケージを直接入手",
        name: "APK",
        description: "GitHub Releases から APK を入手します。インストール手順と SHA-256 の確認方法もご覧ください。",
        links: [
          { label: "リリースから入手する", href: release },
          { label: "インストール手順とハッシュの確認", href: androidReleaseNotes },
        ],
      },
    ],
  },
  {
    name: "iOS",
    requirements: "Xcode の iOS Simulator 専用",
    methods: [
      { label: "ストアなどからインストール", name: "App Store" },
      {
        label: "パッケージを直接入手",
        name: "Simulator 用 .app ZIP",
        developmentStatus: "開発中",
        description: "GitHub Release に添付された場合に入手できる開発用パッケージです。iPhone・iPad にはインストールできません。",
        links: [
          { label: "GitHub Release を確認", href: release },
          { label: "Simulator 用パッケージの説明", href: releaseNotesFile },
        ],
      },
    ],
    note: "警告：iOS 版は開発中で、正常に動作しません。Simulator での検証目的以外には使用しないでください。",
    warning: true,
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
        <span className={method.developmentStatus ? "download-status development" : available ? "download-status available" : "download-status"}>
          {method.developmentStatus ?? (available ? "利用可能" : "Coming soon")}
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
        {platform.note && <p className={platform.warning ? "download-note warning" : "download-note"}>{platform.note}</p>}
      </div>
    </section>
  );
}
