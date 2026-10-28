import type { Metadata } from "next";
import "./globals.css";

const baseUrl =
  process.env.NEXT_PUBLIC_BASE_URL || "https://prelis.prj.kupac.co.jp";

export const metadata: Metadata = {
  metadataBase: new URL(baseUrl),
  title: "Prelis | マルチプラットフォームの PoC アプリ",
  description: "デスクトップ・Android・iOS・ウェブ向けの Prelis を紹介します。Windows 版は Microsoft Store から入手できます。各版の利用方法と開発中の iOS 版に関する注意点をご案内します。",
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
