import type { Metadata } from "next";
import { LegalPage, V } from "../Legal";
import { LEGAL } from "../site";

export const metadata: Metadata = {
  title: "Legal Notice – Grit",
  robots: { index: false },
  alternates: { canonical: "/legal-notice/" },
};

// Impressum nach deutschem Recht (§ 5 DDG, § 18 Abs. 2 MStV), auf Englisch.
export default function LegalNotice() {
  return (
    <LegalPage title="Legal Notice" subtitle="Impressum">
      <h2>Information pursuant to § 5 DDG (German Digital Services Act)</h2>
      <p>
        <V>{LEGAL.name}</V>
        <br />
        <V>{LEGAL.street}</V>
        <br />
        <V>{LEGAL.city}</V>
        <br />
        {LEGAL.country}
      </p>

      <h2>Contact</h2>
      <p>
        Email: <V>{LEGAL.email}</V>
      </p>

      <h2>Responsible for content pursuant to § 18 (2) MStV</h2>
      <p>
        <V>{LEGAL.name}</V>, address as above.
      </p>

      <h2>Liability for content</h2>
      <p>
        The content of this website has been created with care. However, no guarantee can be given for its accuracy,
        completeness or timeliness. Grit is an alpha release and is provided as is, without warranty of any kind.
      </p>

      <h2>Liability for links</h2>
      <p>
        This website contains links to external websites, in particular the BeamNG forum. I have no influence on their
        content; the respective provider is responsible for it. No legal violations were apparent at the time of linking.
        If I become aware of any infringement, I will remove the link immediately.
      </p>

      <h2>Copyright and trademarks</h2>
      <p>
        Unless stated otherwise, Grit and the texts, images and screenshots on this website are licensed under{" "}
        <a href="https://creativecommons.org/licenses/by-nc-sa/4.0/" target="_blank" rel="noopener">
          CC BY-NC-SA 4.0
        </a>
        . BeamNG and BeamNG.drive are trademarks of BeamNG GmbH. Grit is an unofficial fan project and is not affiliated
        with BeamNG GmbH.
      </p>
    </LegalPage>
  );
}
