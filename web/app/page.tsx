import BeforeAfter from "./BeforeAfter";
import { AlphaBar, SiteFooter, SiteHeader } from "./Chrome";
import { asset, FORUM_URL, GAME_VERSION, STAGE, VERSION } from "./site";

function DownloadButton({ label = "Download on BeamNG.com" }: { label?: string }) {
  return (
    <a className="btn btn-primary" href={FORUM_URL} target="_blank" rel="noopener">
      <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
        <path d="M12 4v11m0 0l-4.5-4.5M12 15l4.5-4.5M5 19.5h14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      {label}
    </a>
  );
}

function Shot({ src, alt, caption }: { src: string; alt: string; caption?: string }) {
  return (
    <figure className="shot">
      <a href={asset(src)} target="_blank" rel="noopener">
        <img src={asset(src)} alt={alt} loading="lazy" />
      </a>
      {caption && <figcaption>{caption}</figcaption>}
    </figure>
  );
}

const stats = [
  { value: "≈1 ms", label: "to bake one new decal" },
  { value: "<1 ms", label: "per frame when nothing happens" },
  { value: "500", label: "dirt & scratch layers per car" },
  { value: "0", label: "game files changed" },
];

export default function Home() {
  return (
    <>
      <AlphaBar />
      <SiteHeader />

      <main id="top">
        {/* Hero */}
        <section className="hero">
          <div className="wrap hero-inner">
            <div className="hero-mark">
              <img src={asset("/img/wordmark.webp")} alt="Grit" width={1200} height={458} />
            </div>
            <div className="hero-copy">
              <p className="eyebrow">
                <span className="alpha-chip">{STAGE} · v{VERSION}</span> BeamNG.drive mod
              </p>
              <h1>
                Dynamic dirt, scratches <span className="nowrap">&amp; cracks</span> for every vehicle.
              </h1>
              <p className="lead">
                Scrape along a guardrail and the paint shows it. Drive off-road and mud piles up behind the wheels. Grit
                gives every car a history, in the color of the ground you drive on.
              </p>
              <div className="cta-row">
                <DownloadButton />
                <a className="btn btn-ghost" href="#compare">
                  See it in action
                </a>
              </div>
              <p className="hero-warning">
                Fully playable alpha: install it and drive. If something looks off, let us know in the forum thread.
              </p>
              <ul className="facts">
                <li>Vanilla &amp; modded cars</li>
                <li>Keeps your paint and liveries</li>
                <li>Free · CC BY-NC-SA 4.0</li>
              </ul>
            </div>
          </div>
        </section>

        {/* Vergleich */}
        <section id="compare" className="wrap compare">
          <BeforeAfter
            before={asset("/img/mud-before.webp")}
            after={asset("/img/mud-after.webp")}
            alt="Pickup truck"
          />
          <p className="note">Drag to compare. Same truck, same spot, before and after an off-road run.</p>
        </section>

        {/* Kurzüberblick */}
        <section id="features" className="wrap intro">
          <h2>Not a preset. Not a skin.</h2>
          <p>
            Grit reacts to what actually happens to your car. It works on <strong>every vehicle</strong>, finds the
            painted parts on its own and puts everything on its own texture layer, so your paint, liveries and paint
            designs stay untouched.
          </p>
          <ol className="pillars">
            <li>
              <span className="num">01</span>
              <h3>Scratches</h3>
              <p>Exactly where the body hit, in the direction of the slide.</p>
            </li>
            <li>
              <span className="num">02</span>
              <h3>Dirt &amp; mud</h3>
              <p>Wheel spray and body contact, colored by the surface.</p>
            </li>
            <li>
              <span className="num">03</span>
              <h3>Dust &amp; washing</h3>
              <p>Dust settles at speed. Water washes it off again.</p>
            </li>
            <li>
              <span className="num">04</span>
              <h3>Cracks</h3>
              <p>Hairline and spiderweb cracks in dented plastic.</p>
            </li>
          </ol>
        </section>

        {/* Kratzer */}
        <section className="feature">
          <div className="wrap">
            <img className="feature-head" src={asset("/img/header-scratches.webp")} alt="Scratches" width={1600} height={360} loading="lazy" />
            <div className="feature-body">
              <ul className="bullets">
                <li>Scrapes against walls, guardrails, rocks and other hard surfaces leave scratches exactly where the contact happened.</li>
                <li>Three depths: light clear-coat scuff, primer, bare metal. A longer or harder slide cuts deeper.</li>
                <li>Scratches follow the direction of the slide. Bushes, fabric and water never scratch.</li>
              </ul>
              <div className="media">
                <BeforeAfter
                  before={asset("/img/scratch-before.webp")}
                  after={asset("/img/scratch-after.webp")}
                  alt="Sedan front after a scrape"
                />
              </div>
            </div>
          </div>
        </section>

        {/* Dreck */}
        <section className="feature">
          <div className="wrap">
            <img className="feature-head" src={asset("/img/header-dirt.webp")} alt="Dirt & mud" width={1600} height={360} loading="lazy" />
            <div className="feature-body">
              <ul className="bullets">
                <li><strong>Wheel spray:</strong> dirt, mud, sand, gravel, grass or snow lands on the body behind each wheel and on the rear.</li>
                <li><strong>Contact dirt:</strong> roll into a ditch or slide along an embankment and the dirt stays right at that spot.</li>
                <li><strong>Color by surface:</strong> mud is dark brown, sand is light, snow is white.</li>
                <li>Dirt lies on top of scratches and cracks.</li>
              </ul>
              <div className="media media-grid">
                <Shot src="/img/mud.webp" alt="Mud thrown onto the body behind the wheels" caption="Wheel spray from an off-road track" />
                <Shot src="/img/rollover.webp" alt="Sedan covered in dirt and grass after a rollover" caption="Contact dirt after a rollover on grass" />
              </div>
            </div>
          </div>
        </section>

        {/* Staub & Waschen */}
        <section className="feature">
          <div className="wrap">
            <img className="feature-head" src={asset("/img/header-dust.webp")} alt="Dust & washing" width={1600} height={360} loading="lazy" />
            <div className="feature-body">
              <ul className="bullets">
                <li><strong>Dust:</strong> at speed on dusty ground a fine layer settles on the rear, the lower sides and the top.</li>
                <li><strong>Washing:</strong> drive into water and everything below the waterline gets cleaner step by step. A splash through a ford removes a little, standing in water cleans fully.</li>
                <li><strong>Wet dirt &amp; drying:</strong> fresh mud goes on dark and wet and dries lighter in about a minute and a half, faster at speed.</li>
                <li>Scratches and cracks stay when you wash.</li>
              </ul>
              <div className="media">
                <Shot src="/img/dust.webp" alt="Dust layer after a fast gravel run" caption="Dust after a fast gravel run" />
              </div>
            </div>
          </div>
        </section>

        {/* Risse & App */}
        <section className="wrap duo">
          <div className="panel">
            <p className="eyebrow">Damage</p>
            <h2>Cracks</h2>
            <p>
              When a painted plastic part like a bumper gets dented or breaks, hairline or spiderweb cracks appear right
              at that spot. Bigger dents give bigger cracks. Unpainted black plastic and glass stay vanilla, and cracks
              survive washing just like scratches.
            </p>
          </div>
          <div className="panel">
            <p className="eyebrow">In-game app</p>
            <h2>Your car, your rules</h2>
            <p>
              Add the <strong>Grit</strong> app from the UI apps menu. It sits as a small “Grit ▾” tab and folds out on
              click.
            </p>
            <ul className="bullets compact">
              <li>Dirt, scratches and cracks on or off</li>
              <li>Dirt strength 0.25–2, drying speed 0.25–4</li>
              <li><strong>Wash</strong> (damage stays) and <strong>Clear all</strong></li>
              <li>Saved in <code>settings/grit.json</code></li>
            </ul>
          </div>
        </section>

        {/* Leistung */}
        <section className="wrap perf">
          <div className="perf-copy">
            <p className="eyebrow">Performance</p>
            <h2>Measured in game, not estimated.</h2>
            <p>
              New decals are mostly computed instead of projected, so a frame in which Grit adds dirt takes as long as a
              normal one. No stutter while you plough through mud.
            </p>
          </div>
          <dl className="stats">
            {stats.map((s) => (
              <div key={s.label}>
                <dt>{s.value}</dt>
                <dd>{s.label}</dd>
              </div>
            ))}
          </dl>
        </section>

        {/* Installation */}
        <section id="install" className="wrap install">
          <p className="eyebrow">Installation</p>
          <h2>Three steps, then drive.</h2>
          <ol className="steps">
            <li>
              <h3>Download</h3>
              <p>
                Get <code>grit_v{VERSION}.zip</code> from the BeamNG.com repository page.
              </p>
            </li>
            <li>
              <h3>Drop it in</h3>
              <p>
                Put the zip into <code>%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\</code>. Do not unpack it.
              </p>
            </li>
            <li>
              <h3>Enable &amp; drive</h3>
              <p>
                Enable <strong>Grit</strong> in the mod manager and spawn a car. It respawns once at the start, then Grit
                runs on its own.
              </p>
            </li>
          </ol>
          <aside className="callout" role="note">
            <span className="alpha-chip">{STAGE}</span>
            <div>
              <strong>Ready to use, still growing.</strong> Grit works out of the box on any car. As an alpha it can
              still have the occasional bug or visual glitch, and details may change between versions. Spotted something?
              Post your vehicle, map and a screenshot in the forum thread, it helps a lot.
            </div>
          </aside>
          <div className="cta-row center">
            <DownloadButton />
          </div>
          <p className="note center">
            Built and tested on BeamNG.drive {GAME_VERSION} with the ETK I-Series, Gavril D-Series, Ibishu Covet and the
            modded Gavril Vertex NA2.
          </p>
        </section>

        {/* Einschränkungen */}
        <section id="limits" className="wrap limits">
          <p className="eyebrow">{STAGE} · known issues</p>
          <h2>Good to know</h2>
          <details>
            <summary>Light scratches are hard to see on white or chrome</summary>
            <p>They are light on light. On dark paint they show up clearly.</p>
          </details>
          <details>
            <summary>Some cars only scratch low on the body</summary>
            <p>Vehicles with collision points only near the sills and bumper corners keep guardrail scratches down there.</p>
          </details>
          <details>
            <summary>Shared texture areas on some models</summary>
            <p>
              Some models reuse the same spot of their decal texture (UV1) for several parts. On the Ibishu Covet both
              bumpers share one stretched area, so a scratch there can show up on both. <code>grit_main.uvCheck()</code>{" "}
              in the Lua console shows the layout of any car, <code>grit_main.clear()</code> turns it off.
            </p>
          </details>
          <details>
            <summary>Player car only, nothing saved yet</summary>
            <p>
              AI traffic gets no Grit for now. Dirt and damage are gone after a reset, a repair or a restart. Other dirt or
              scratch mods may conflict, use one at a time.
            </p>
          </details>
          <details>
            <summary>What&apos;s planned?</summary>
            <p>Rain that slowly washes the car, and optional dirt and scratches on AI traffic.</p>
          </details>
        </section>
      </main>

      <SiteFooter />
    </>
  );
}
