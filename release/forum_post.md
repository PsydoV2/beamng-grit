# Forum-Beitrag Grit v0.5.0

Zum Einfügen in den BeamNG-Mod-Upload (XenForo, BBCode). Vorher hochladen bzw. anhängen:

- Vorschaubild (Thumbnail): `branding/out/grit-thumbnail.png`
- Im Text: `grit-banner.png`, `grit-header-scratches.png`, `grit-header-dirt.png`, `grit-header-dust.png`
  (die `[IMG]`-Platzhalter unten durch die Bild-Links bzw. Anhänge ersetzen)
- Datei: `build/grit_v0.5.0.zip`

**Titel:** Grit – Dynamic Dirt, Scratches & Cracks for every vehicle
**Kurzbeschreibung (Tagline):** Your car keeps a history: scratches where you hit, dirt from the ground you drive on.
**Version:** 0.5.0

---

```bbcode
[IMG]grit-banner.png[/IMG]

[B]Grit[/B] gives every car in BeamNG.drive a history. Scrape along a guardrail and the paint shows it. Drive off-road and mud piles up behind the wheels. Fast gravel runs leave a layer of dust on the car. Everything builds up gradually, and the dirt takes its color from the ground you drive on.

Grit is not a preset or a skin. It works on [B]every vehicle[/B], including modded ones, and leaves your paint and liveries untouched.

[I]Version 0.5.0 – early test release, built and tested on BeamNG.drive 0.40.5.0. Feedback and screenshots are very welcome.[/I]

[IMG]grit-header-scratches.png[/IMG]
[SIZE=5][B]Scratches[/B][/SIZE]
[LIST]
[*]Body scrapes against walls, guardrails, rocks and other hard surfaces leave scratches exactly where the contact happened.
[*]Three depths: light clear-coat scuff, primer, bare metal. A longer or harder slide cuts deeper.
[*]Scratches follow the direction of the slide. Bushes, fabric and water never scratch.
[/LIST]

[SIZE=5][B]Cracks[/B][/SIZE]
[LIST]
[*]When a painted plastic part such as a bumper gets dented or breaks, hairline or spiderweb cracks appear right at that spot.
[*]Unpainted black plastic and glass stay as they are.
[/LIST]

[IMG]grit-header-dirt.png[/IMG]
[SIZE=5][B]Dirt[/B][/SIZE]
[LIST]
[*][B]Wheel spray:[/B] dirt, mud, sand, gravel, grass or snow is thrown onto the body behind each wheel and onto the rear.
[*][B]Contact dirt:[/B] roll into a ditch or slide along an embankment and the dirt stays right at that spot.
[*][B]Color by surface:[/B] mud is dark brown, sand is light, snow is white.
[*]Dirt lies on top of scratches and cracks.
[/LIST]

[IMG]grit-header-dust.png[/IMG]
[SIZE=5][B]Dust, washing & drying[/B][/SIZE]
[LIST]
[*][B]Dust:[/B] at speed on dusty ground a fine layer settles on the rear, the lower sides and the top.
[*][B]Washing:[/B] drive into water and everything below the waterline gets cleaner step by step. Scratches and cracks stay.
[*][B]Wet dirt and drying:[/B] fresh mud goes on dark and wet and dries lighter over about a minute and a half, faster at speed.
[/LIST]

[SIZE=5][B]In-game app[/B][/SIZE]
Add the [B]Grit[/B] app from the UI apps menu. It sits as a small "Grit ▾" tab and folds out on click:
[LIST]
[*]switch dirt, scratches and cracks on or off
[*]dirt strength (0.25–2) and drying speed (0.25–4)
[*][B]Wash[/B] (cleans everything, damage stays) and [B]Clear all[/B]
[/LIST]
Settings are saved in [ICODE]settings/grit.json[/ICODE] in your user folder.

[SIZE=5][B]Installation[/B][/SIZE]
[LIST=1]
[*]Put [ICODE]grit_v0.5.0.zip[/ICODE] into [ICODE]%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\[/ICODE]. Do not unpack it.
[*]Start the game and make sure [B]Grit[/B] is enabled in the mod manager.
[*]Spawn a vehicle and drive. Grit activates on its own. The car respawns once at the start (under a second).
[/LIST]
Repairing or resetting the vehicle removes all dirt and damage.

[SIZE=5][B]Compatibility & performance[/B][/SIZE]
[LIST]
[*]Vanilla and modded cars. Tested on ETK I-Series, Gavril D-Series, Ibishu Covet and the modded Gavril Vertex NA2.
[*]Uses its own texture layer and skin slot, so paint, liveries and paint designs stay as they are.
[*]Every car has its own dirt and scratches, even several copies of the same model.
[*]Other scratch or dirt mods may conflict. Use only one at a time.
[*]Measured in game: no stutter while driving through mud, washing a step costs about 1 ms, idle well under 1 ms per frame.
[/LIST]

[SIZE=5][B]Known limitations[/B][/SIZE]
[LIST]
[*]Light scratches and dust are hard to see on white or chrome parts. They show up clearly on dark paint.
[*]Some vehicles only have collision points low on the body, so guardrail scratches stay near the sills and bumper corners.
[*]Some models reuse the same spot of their decal texture for several parts. On the Ibishu Covet both bumpers share one stretched area, so a scratch there can show up on both as a large patch. [ICODE]grit_main.uvCheck()[/ICODE] in the Lua console shows the layout of any car, [ICODE]grit_main.clear()[/ICODE] turns it off.
[*]Only the player vehicle gets Grit for now.
[*]Dirt and scratches are not saved yet. They are gone after a reset, a repair or a restart.
[/LIST]

[SIZE=5][B]Planned[/B][/SIZE]
Rain slowly washing the car, optional dirt and scratches on AI traffic.

[SIZE=5][B]License & credits[/B][/SIZE]
Licensed under [URL='https://creativecommons.org/licenses/by-nc-sa/4.0/']CC BY-NC-SA 4.0[/URL]: share and modify, no commercial use, credit Grit and Psydo, same license for modified versions.
Grit uses only the game's own Lua APIs, changes no game files and contains no code or assets from other mods.
Idea and testing: Psydo. Development with Claude.
```
