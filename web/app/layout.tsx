import type { Metadata, Viewport } from "next";
import { Barlow, Barlow_Condensed } from "next/font/google";
import { asset } from "./site";
import "./globals.css";

// Barlow ist der DIN-Schrift Bahnschrift aus dem Branding am nächsten.
const body = Barlow({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-body" });
const display = Barlow_Condensed({ subsets: ["latin"], weight: ["600", "700"], variable: "--font-display" });

const description =
  "Grit gives every car in BeamNG.drive a history: scratches where you scrape, mud behind the wheels, dust after fast gravel runs and cracks in plastic. Works on every vehicle, vanilla and modded.";

export const metadata: Metadata = {
  title: "Grit (Alpha) – Dynamic Dirt, Scratches & Cracks for BeamNG.drive",
  description,
  icons: { icon: asset("/img/icon.png") },
  openGraph: {
    title: "Grit – Dynamic Dirt, Scratches & Cracks for every vehicle",
    description,
    type: "website",
    images: [{ url: asset("/img/og.jpg"), width: 1200, height: 400 }],
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
