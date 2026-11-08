import { GAME_VERSION, VERSION } from "./site";

// Fragen und Antworten für die FAQ auf der Startseite und das FAQPage-Schema (JSON-LD).
// Erster Satz jeder Antwort beantwortet die Frage direkt, damit Suchmaschinen und KI ihn zitieren können.
// `code` in Backticks wird auf der Seite als <code> dargestellt.
export const FAQ: { q: string; a: string }[] = [
  {
    q: "What is Grit?",
    a: `Grit is a free mod for BeamNG.drive that adds dynamic dirt, mud, dust, scratches and plastic cracks to your car based on what actually happens while you drive. Scrapes leave scratches where the body hit, wheels throw mud in the color of the ground, and water washes the dirt off again.`,
  },
  {
    q: "Does Grit work with modded cars?",
    a: "Yes. Grit works on every vehicle, vanilla and modded. It finds the painted parts of a car on its own, so no per-vehicle setup is needed.",
  },
  {
    q: "Is Grit free?",
    a: "Yes. Grit is free and licensed under CC BY-NC-SA 4.0. You download it from its BeamNG.com repository page.",
  },
  {
    q: "Does Grit change my paint or livery?",
    a: "No. Grit draws dirt and damage on its own texture layer on top of the paint, so your paint, liveries and paint designs stay untouched. It also changes no game files.",
  },
  {
    q: "Does Grit hurt FPS?",
    a: "Barely. Baking a new decal takes about 1 ms and an idle frame costs less than 1 ms. Most new dirt is computed instead of projected, so frames in which Grit adds dirt are no slower than normal frames.",
  },
  {
    q: "Which BeamNG.drive version does Grit support?",
    a: `Grit ${VERSION} is built and tested on BeamNG.drive ${GAME_VERSION} with the ETK I-Series, Gavril D-Series, Ibishu Covet and the modded Gavril Vertex NA2.`,
  },
  {
    q: "How do I clean my car?",
    a: "Drive into water: everything below the waterline gets cleaner step by step. You can also press Wash in the Grit app (scratches and cracks stay) or Clear all, and a vehicle reset removes everything.",
  },
  {
    q: "Why are scratches hard to see on white or chrome?",
    a: "They are light on light. On dark paint they show up clearly.",
  },
  {
    q: "Why does my car only get scratches low on the body?",
    a: "Some vehicles only have collision points near the sills and bumper corners, so guardrail scratches stay down there.",
  },
  {
    q: "Why does a scratch show up on two parts at once?",
    a: "Some models reuse the same spot of their decal texture (UV1) for several parts. On the Ibishu Covet both bumpers share one stretched area, so a scratch there can show up on both. `grit_main.uvCheck()` in the Lua console shows the layout of any car, `grit_main.clear()` removes it.",
  },
  {
    q: "Does Grit work on AI traffic, and is dirt saved?",
    a: "Not yet. Grit currently runs on the player car only, and dirt and damage are gone after a reset, a repair or a restart. Other dirt or scratch mods may conflict, so use one at a time.",
  },
  {
    q: "What's planned for Grit?",
    a: "Rain that slowly washes the car, and optional dirt and scratches on AI traffic.",
  },
];

// Antwort ohne Backticks für das Schema.
export const plain = (s: string) => s.replace(/`/g, "");
