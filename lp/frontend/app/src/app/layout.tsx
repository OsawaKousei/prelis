import type { Metadata } from "next";
import "./globals.css";

const baseUrl =
  process.env.NEXT_PUBLIC_BASE_URL || "https://prelis.prj.kupac.co.jp";

export const metadata: Metadata = {
  metadataBase: new URL(baseUrl),
  title: "Prelis | マルチプラットフォームの PoC アプリ",
  description: "デスクトップ・Android・ウェブで Diary・Timer・Password を提供する PoC アプリです。各版の利用方法とウェブ版の注意点をご案内します。",
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
