export const FORUM_URL =
  "https://www.beamng.com/resources/grit-%E2%80%93-dynamic-dirt-scratches-cracks-for-every-vehicle.40240/";

export const VERSION = "0.6.0";
export const STAGE = "Alpha";

// Angaben für Impressum und Datenschutz. Platzhalter in eckigen Klammern werden auf den
// Seiten orange markiert, bis sie ersetzt sind. Vor dem Veröffentlichen ausfüllen!
export const LEGAL = {
  name: "Sebastian Falter",
  street: "[Street and number]",
  city: "[Postcode, city]",
  country: "Germany",
  email: "info@sfalter.de",
  hoster: "IONOS",
  logDays: "?",
  updated: "November 2026",
};
export const GAME_VERSION = "0.40.5.0";

// Bilder liegen in public/, beim Export unter einem Unterpfad (GitHub Pages) braucht es das Präfix.
export const asset = (p: string) =>
  `${process.env.NEXT_PUBLIC_BASE_PATH || ""}${p}`;

// Öffentliche Adresse (Canonical, Open Graph, Sitemap, JSON-LD). Sitemap in public/sitemap.xml mitpflegen.
export const SITE_URL = "https://grit.sfalter.de";
// Stand der Seite / der aktuellen Version (ISO-Datum), für JSON-LD und „Last updated“.
export const UPDATED = "2026-11-13";
