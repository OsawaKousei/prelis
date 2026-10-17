import type { Metadata } from "next";
import "./globals.css";

const baseUrl =
  process.env.NEXT_PUBLIC_BASE_URL || "https://prelis.prj.kupac.co.jp";

export const metadata: Metadata = {
  metadataBase: new URL(baseUrl),
  title: "Prelis | マルチプラットフォームの PoC アプリ",
  description: "デスクトップとモバイルに向けて開発するマルチプラットフォームの PoC アプリです。対応 OS ごとの入手方法をご案内します。",
  alternates: { canonical: "/" },
  icons: { icon: "/brand.png" },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
