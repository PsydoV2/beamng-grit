"use client";

import { useState } from "react";

type Props = {
  before: string;
  after: string;
  alt: string;
  start?: number;
};

// Vorher/Nachher-Vergleich. Ein unsichtbarer Range-Input über dem Bild übernimmt
// Ziehen, Tippen und Tastatur, dadurch ohne eigene Pointer-Logik barrierefrei.
export default function BeforeAfter({ before, after, alt, start = 50 }: Props) {
  const [pos, setPos] = useState(start);

  return (
    <div className="ba" style={{ ["--pos" as string]: `${pos}%` }}>
      <img className="ba-img" src={after} alt={`${alt}, with Grit`} loading="lazy" />
      <img className="ba-img ba-before" src={before} alt={`${alt}, clean`} loading="lazy" aria-hidden="true" />
      <span className="ba-label ba-label-l">Clean</span>
      <span className="ba-label ba-label-r">With Grit</span>
      <span className="ba-handle" aria-hidden="true">
        <span className="ba-knob">
          <svg viewBox="0 0 24 24" width="18" height="18">
            <path d="M9 6l-6 6 6 6M15 6l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
      </span>
      <input
        className="ba-range"
        type="range"
        min={0}
        max={100}
        step={0.5}
        value={pos}
        onChange={(e) => setPos(Number(e.target.value))}
        aria-label="Compare clean and with Grit"
      />
    </div>
  );
}
