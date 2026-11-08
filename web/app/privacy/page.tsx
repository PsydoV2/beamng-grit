import type { Metadata } from "next";
import { LegalPage, V } from "../Legal";
import { LEGAL } from "../site";

export const metadata: Metadata = {
  title: "Privacy Policy – Grit",
  robots: { index: false },
  alternates: { canonical: "/privacy/" },
};

// Datenschutzerklärung nach DSGVO, auf Englisch.
export default function Privacy() {
  return (
    <LegalPage title="Privacy Policy" subtitle="Datenschutzerklärung">
      <h2>1. Controller</h2>
      <p>
        <V>{LEGAL.name}</V>
        <br />
        <V>{LEGAL.street}</V>
        <br />
        <V>{LEGAL.city}</V>
        <br />
        {LEGAL.country}
        <br />
        Email: <V>{LEGAL.email}</V>
      </p>

      <h2>2. In short</h2>
      <p>
        This is a plain information page. It sets <strong>no cookies</strong> and embeds no third-party content. Fonts and
        images are served from the same server as the page, so your browser does not connect to Google or any other
        service. Besides the technically necessary server log files, I use a self-hosted, cookieless instance of Umami
        for anonymous visitor statistics (see section 4).
      </p>

      <h2>3. Hosting and server log files</h2>
      <p>
        This website is hosted by: <V>{LEGAL.hoster}</V>.
      </p>
      <p>
        When you visit the website, the hosting provider automatically stores information sent by your browser: IP
        address, date and time of access, requested file or URL, referrer URL, browser type and version, and operating
        system. This data is needed to deliver the website and to keep the server secure and stable.
      </p>
      <p>
        The legal basis is Art. 6 (1) (f) GDPR (legitimate interest in a secure and working website). Log files are deleted
        after <V>{LEGAL.logDays}</V> days. A data processing agreement pursuant to Art. 28 GDPR is in place with the hosting
        provider.
      </p>

      <h2>4. Visitor statistics (Umami)</h2>
      <p>
        This website uses Umami, an open-source analytics tool that I host myself at webstats.sfalter.de. No data is
        passed to third parties. Umami sets no cookies and does not store your full IP address. It records which pages are
        visited, the referrer, browser, operating system, device type, screen size, language and country (derived from the
        IP address). In addition, the session recording records how the page is used (scrolling, mouse movements and
        clicks) so that I can improve the page.
      </p>
      <p>
        The legal basis is Art. 6 (1) (f) GDPR (legitimate interest in understanding how the website is used and improving
        it). You can prevent the collection by blocking JavaScript or the domain webstats.sfalter.de in your browser.
      </p>

      <h2>5. External links</h2>
      <p>
        This website links to the BeamNG forum (beamng.com) and to creativecommons.org. You only leave this website when you
        click such a link. From then on, the privacy policy of the respective provider applies.
      </p>

      <h2>6. Contact by email</h2>
      <p>
        If you email me, I process your address and message only to answer your request (Art. 6 (1) (f) GDPR). The data is
        deleted once the request has been dealt with, unless statutory retention obligations apply.
      </p>

      <h2>7. Your rights</h2>
      <p>You have the right at any time to</p>
      <ul>
        <li>access the data stored about you (Art. 15 GDPR),</li>
        <li>rectification (Art. 16 GDPR),</li>
        <li>erasure (Art. 17 GDPR),</li>
        <li>restriction of processing (Art. 18 GDPR),</li>
        <li>data portability (Art. 20 GDPR),</li>
        <li>object to processing (Art. 21 GDPR).</li>
      </ul>
      <p>
        You also have the right to lodge a complaint with a data protection supervisory authority (Art. 77 GDPR), for
        example the authority where you live.
      </p>

      <h2>8. The mod itself</h2>
      <p>
        Grit runs locally inside BeamNG.drive. The mod sends no data to the internet; settings are stored only on your
        computer in <code>settings/grit.json</code>.
      </p>

      <p className="muted">Last updated: {LEGAL.updated}</p>
    </LegalPage>
  );
}
