# Forum-Beitrag Grit v0.6.0

Zum Einfügen in den BeamNG-Mod-Upload (XenForo, BBCode). Stand: Beitrag, wie er im Forum steht (Layout von Psydo),
mit den Änderungen für 0.6.0.

- Die Bilder sind schon im Forum hochgeladen, `[ATTACH=full]<Nummer>[/ATTACH]` verweist auf diese Anhänge:
  1352059 Banner, 1352061 Kopf Kratzer, 1352075 Kratzer-Screenshot, 1352062 Kopf Dreck, 1352074 Schlamm-Screenshot,
  1352063 Kopf Staub, 1352073 Staub-Screenshot. Neue Bilder: hochladen und die Nummer aus dem Editor übernehmen.
- Vorschaubild (Thumbnail): `branding/out/grit-thumbnail.png`
- Datei: `build/grit_v0.6.0.zip`

**Titel:** Grit – Dynamic Dirt, Scratches & Cracks for every vehicle
**Tagline (Subtitle):** Dynamic dirt, scratches and cracks for every vehicle
**Tags** (nur vorhandene erlaubt): lua, offroad, rally, app, user interface, experimental
**Version:** 0.6.0

---

```bbcode
[ATTACH=full]1352059[/ATTACH]

[B]Grit[/B] gives every car in BeamNG.drive a history. Scrape along a guardrail and the paint shows it. Drive off-road and mud piles up behind the wheels. Fast gravel runs leave a layer of dust on the car. Everything builds up gradually, and the dirt takes its color from the ground you drive on.

Grit is not a preset or a skin. It works on [B]every vehicle[/B], including modded ones, and leaves your paint and liveries untouched.

[I]Version 0.6.0 – early test release, built and tested on BeamNG.drive 0.40.5.0. Feedback and screenshots are very welcome.[/I]

[SIZE=5][B]What's new in 0.6.0[/B][/SIZE]
[LIST]
[*]Three scratch shapes per depth, randomly turned, so long scrapes look less repetitive.
[*]New [B]scratch sensitivity[/B] slider in the Grit app.
[*]Liveries with fixed colors, for example police skins, now get dirt and scratches.
[*]New console command [B]grit_main.report()[/B] for bug reports (see below).
[*]Fixed: Clear all left the most recent decal visible.
[/LIST]

[SIZE=5][B][ATTACH=full]1352061[/ATTACH][/B]
[B]Scratches[/B][/SIZE]
[LIST]
[*]Body scrapes against walls, guardrails, rocks and other hard surfaces leave scratches exactly where the contact happened.
[*]Three depths: light clear-coat scuff, primer, bare metal. A longer or harder slide cuts deeper. Each depth comes in three shapes, randomly turned.
[*]Scratches follow the direction of the slide. Bushes, fabric and water never scratch.
[/LIST]

[ATTACH=full]1352075[/ATTACH]

[SIZE=5]
[B]Cracks[/B][/SIZE]
[LIST]
[*]When a painted plastic part such as a bumper gets dented or breaks, hairline or spiderweb cracks appear right at that spot.
[*]Unpainted black plastic and glass stay as they are.
[/LIST]

[ATTACH=full]1352062[/ATTACH]
[SIZE=5][B]Dirt[/B][/SIZE]
[LIST]
[*][B]Wheel spray:[/B] dirt, mud, sand, gravel, grass or snow is thrown onto the body behind each wheel and onto the rear.
[*][B]Contact dirt:[/B] roll into a ditch or slide along an embankment and the dirt stays right at that spot.
[*][B]Color by surface:[/B] mud is dark brown, sand is light, snow is white.
[*]Dirt lies on top of scratches and cracks.
[/LIST]

[B][SIZE=5][ATTACH=full]1352074[/ATTACH] 


[ATTACH=full]1352063[/ATTACH] 
Dust, washing & drying[/SIZE][/B]
[LIST]
[*][B]Dust:[/B] at speed on dusty ground a fine layer settles on the rear, the lower sides and the top.
[*][B]Washing:[/B] drive into water and everything below the waterline gets cleaner step by step. Scratches and cracks stay.
[*][B]Wet dirt and drying:[/B] fresh mud goes on dark and wet and dries lighter over about a minute and a half, faster at speed.
[/LIST]
[ATTACH=full]1352073[/ATTACH]


[SIZE=5][B]In-game app[/B][/SIZE]
Add the [B]Grit[/B] app from the UI apps menu. It sits as a small "Grit ▾" tab and folds out on click:
[LIST]
[*]switch dirt, scratches and cracks on or off
[*]dirt strength (0.25–2), drying speed (0.25–4) and scratch sensitivity (0.5–2, higher scratches more easily)
[*][B]Wash[/B] (cleans everything, damage stays) and [B]Clear all[/B]
[/LIST]
Settings are saved in [B]settings/grit.json[/B] in your user folder.

[SIZE=5][B]Installation[/B][/SIZE]
[LIST=1]
[*]Put [B]grit_v0.6.0.zip[/B] into [B]%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\[/B]. Do not unpack it. Remove older Grit zips first.
[*]Start the game and make sure [B]Grit[/B] is enabled in the mod manager.
[*]Spawn a vehicle and drive. Grit activates on its own. The car respawns once at the start (under a second).
[/LIST]
Repairing or resetting the vehicle removes all dirt and damage.

[SIZE=5][B]Compatibility & performance[/B][/SIZE]
[LIST]
[*]Vanilla and modded cars. Tested on ETK I-Series, Gavril D-Series, Gavril Grand Marshal (incl. police livery), Ibishu Covet and the modded Gavril Vertex NA2.
[*]Uses its own texture layer and skin slot, so paint, liveries (also fixed-color ones like police skins) and paint designs stay as they are.
[*]Every car has its own dirt and scratches, even several copies of the same model.
[*]Other scratch or dirt mods may conflict. Use only one at a time.
[*]Measured in game: no stutter while driving through mud, washing a step costs about 1 ms, idle well under 1 ms per frame.
[/LIST]

[SIZE=5][B]Known limitations[/B][/SIZE]
[LIST]
[*]Light scratches and dust are hard to see on white or chrome parts. They show up clearly on dark paint.
[*]Some vehicles only have collision points low on the body, so guardrail scratches stay near the sills and bumper corners.
[*]Some models reuse the same spot of their decal texture for several parts. On the Ibishu Covet both bumpers share one stretched area, so a scratch there can show up on both as a large patch. [B]grit_main.uvCheck()[/B] in the Lua console shows the layout of any car, [B]grit_main.clear()[/B] turns it off.
[*]Only the player vehicle gets Grit for now.
[*]Modded and Automation-exported cars depend on how the model was built. Some get dirt only on a few parts or not at all. Please report those (see below).
[*]Dirt and scratches are not saved yet. They are gone after a reset, a repair or a restart.
[/LIST]

[SIZE=5][B]Reporting a bug[/B][/SIZE]
[LIST=1]
[*]Sit in the affected car and open the Lua console (GE context).
[*]Run [B]grit_main.report()[/B]. It writes [B]grit_report.txt[/B] to [B]%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\[/B].
[*]Post the vehicle, configuration or livery and a screenshot, and attach that file. For performance issues, add your FPS with and without Grit.
[/LIST]

[SIZE=5][B]Planned[/B][/SIZE]
Rain slowly washing the car, optional dirt and scratches on AI traffic.

[SIZE=5][B]License & credits[/B][/SIZE]
Licensed under [URL='https://creativecommons.org/licenses/by-nc-sa/4.0/']CC BY-NC-SA 4.0[/URL]: share and modify, no commercial use, credit Grit and Psydo, same license for modified versions.
Grit uses only the game's own Lua APIs, changes no game files and contains no code or assets from other mods.
```

---

## Update-Text (Feld „Update“ beim Hochladen der neuen Version)

**Titel:** 0.6.0 – scratch variants, sensitivity, police liveries, bug report

```bbcode
[LIST]
[*]Scratches now come in three shapes per depth and are randomly turned, so long scrapes look less repetitive.
[*]New [B]scratch sensitivity[/B] slider in the Grit app (0.5–2).
[*]Liveries with fixed colors, for example police skins, now get dirt and scratches.
[*]New console command [B]grit_main.report()[/B]: writes grit_report.txt to your user folder. Please attach it to bug reports.
[*]Fixed: Clear all left the most recent decal visible.
[/LIST]
```
