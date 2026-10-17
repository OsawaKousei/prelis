import type { Metadata } from "next";
import "./globals.css";

const baseUrl =
  process.env.NEXT_PUBLIC_BASE_URL || "https://prelis.prj.kupac.co.jp";

export const metadata: Metadata = {
  metadataBase: new URL(baseUrl),
  title: "Prelis | マルチプラットフォームの PoC アプリ",
  description: "デスクトップと Android 向けの PoC アプリ。日記、1〜180分のタイマー、パスワード生成を実装しています。",
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
