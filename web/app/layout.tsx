import type { Metadata, Viewport } from "next";
import { Barlow, Barlow_Condensed } from "next/font/google";
import { asset, SITE_URL } from "./site";
import "./globals.css";

// Barlow ist der DIN-Schrift Bahnschrift aus dem Branding am nächsten.
const body = Barlow({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-body" });
const display = Barlow_Condensed({ subsets: ["latin"], weight: ["600", "700"], variable: "--font-display" });

// Höchstens ca. 155 Zeichen, sonst kürzt Google.
const description =
  "Free BeamNG.drive mod: dynamic scratches, mud, dust and plastic cracks that react to how you drive. Works on every vanilla and modded car.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Grit – Dynamic Dirt & Scratches Mod for BeamNG.drive",
  description,
  alternates: { canonical: "/" },
  icons: {
    icon: [
      { url: asset("/favicon/favicon.ico"), sizes: "any" },
      { url: asset("/favicon/favicon-32x32.png"), sizes: "32x32", type: "image/png" },
      { url: asset("/favicon/favicon-16x16.png"), sizes: "16x16", type: "image/png" },
    ],
    apple: asset("/favicon/apple-touch-icon.png"),
  },
  manifest: asset("/favicon/site.webmanifest"),
  openGraph: {
    title: "Grit – Dynamic Dirt, Scratches & Cracks for every vehicle",
    description,
    url: "/",
    siteName: "Grit",
    locale: "en_US",
    type: "website",
    images: [{ url: asset("/img/og.jpg"), width: 1200, height: 630, alt: "Grit – dynamic dirt, scratches and cracks for BeamNG.drive" }],
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = { themeColor: "#121417" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${body.variable} ${display.variable}`}>
      <body>{children}</body>
    </html>
  );
}
