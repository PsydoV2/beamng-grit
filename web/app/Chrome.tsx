import Link from "next/link";
import { asset, FORUM_URL, STAGE, VERSION } from "./site";

// Warnleiste ganz oben, auf jeder Seite sichtbar.
export function AlphaBar() {
  return (
    <div className="alphabar" role="note">
      <div className="wrap alphabar-inner">
        <span className="alpha-chip">{STAGE}</span>
        <span>
          <strong>v{VERSION} is out and ready to drive.</strong> It&apos;s an alpha, so you might run into the odd bug.{" "}
          <a href={FORUM_URL} target="_blank" rel="noopener">
            Feedback welcome
          </a>
          .
        </span>
      </div>
    </div>
  );
}

export function SiteHeader({ home = true }: { home?: boolean }) {
  // Auf Unterseiten zeigen die Abschnitts-Links zurück auf die Startseite.
  const base = home ? "" : "/";
  return (
    <header className="nav">
      <div className="wrap nav-inner">
        <Link className="brand" href="/" aria-label="Grit home">
          <img src={asset("/img/logo.png")} alt="" width={24} height={32} />
          <span>Grit</span>
          <span className="alpha-chip alpha-chip-sm">{STAGE}</span>
        </Link>
        <nav className="nav-links" aria-label="Sections">
          <Link href={`${base}#features`}>Features</Link>
          <Link href={`${base}#install`}>Install</Link>
          <Link href={`${base}#limits`}>Limitations</Link>
        </nav>
        <a className="btn btn-small" href={FORUM_URL} target="_blank" rel="noopener">
          Download
        </a>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="wrap footer-inner">
        <div className="brand">
          <img src={asset("/img/logo.png")} alt="" width={24} height={32} />
          <span>Grit</span>
          <span className="alpha-chip alpha-chip-sm">{STAGE}</span>
        </div>
        <p>
          By <strong>Psydo</strong>. Development with Claude. Licensed under{" "}
          <a href="https://creativecommons.org/licenses/by-nc-sa/4.0/" target="_blank" rel="noopener">
            CC BY-NC-SA 4.0
          </a>
          . Uses only the game&apos;s own Lua APIs, changes no game files.
        </p>
        <p className="muted">
          {STAGE} release v{VERSION}, provided as is. Fan-made mod, not affiliated with BeamNG GmbH.
        </p>
        <div className="footer-links">
          <a href={FORUM_URL} target="_blank" rel="noopener">
            Feedback &amp; download on the BeamNG forum →
          </a>
          <span className="footer-legal">
            <Link href="/legal-notice/">Legal Notice (Impressum)</Link>
            <Link href="/privacy/">Privacy Policy</Link>
          </span>
        </div>
      </div>
    </footer>
  );
}
