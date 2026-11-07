// Grit – UI-App (M5.2). Aufbau wie die Vanilla-Apps ui/modules/apps/Winds/app.js (md-slider, bngApi.engineLua)
// und ui/modules/apps/threedexport/app.js (engineLua mit Rückgabe-Callback). Alle Werte liegen in GE-Lua
// (grit_main / settings.lua), die App zeigt sie nur an und ruft grit_main.set / washNow / clear auf.
angular.module('beamng.apps')
.directive('gritApp', ['$timeout', function ($timeout) {
  return {
    template:
      // M5.2 Lauf 1 (Sebastian): auf- und zuklappbar. Lauf 2: mit ng-show und eigenem Flex-Rahmen blieb der Inhalt
      // unsichtbar (nur die Knöpfe als orange Ecken) → ng-if: Inhalt wird beim Aufklappen neu aufgebaut, offen exakt
      // das Layout von Lauf 1. Hintergrund (.bngApp, ui/entrypoints/main/main.css:29) nur am sichtbaren Teil.
      // Lauf 3: der graue Kasten ist der App-Rahmen des Spiels (overlay-item-editor__hover-bg,
      // ui/ui-vue/src/common/modules/overlay/components/OverlayItemEditor.vue:225-232) in Größe aus app.json →
      // Rahmen nur so hoch wie die Kopfzeile (app.json height 28px), das offene Fenster ragt darunter heraus
      // Lauf 4: ragte nicht heraus, sondern scrollte: .ui-app-host hat overflow: hidden
      // (ui/ui-vue/src/modules/apps/components/AppHost.vue Style) → offenes Fenster position: fixed an die Stelle
      // der Kopfzeile (kein transform an den Eltern, das fixed einfangen würde).
      // Lauf 5: Fenster bis 80vh lang (Höhe kam von außen) → height: auto, kein Flex. md-checkbox zeigte true als
      // leeres Kästchen → eigene Schalter (Kästchen orange = an).
      '<div style="position: relative; width: 100%; height: 100%; overflow: visible;">' +
        '<div ng-if="!open" class="bngApp" ng-click="toggle()" style="display: inline-block; padding: 4px 8px; cursor: pointer; font-weight: bold; user-select: none;">Grit &#9662;</div>' +
        '<div ng-if="open" class="bngApp" ng-style="panelStyle" style="position: fixed; width: 280px; height: auto; max-height: 80vh; padding: 8px; overflow-y: auto; display: block; box-sizing: border-box; pointer-events: auto; z-index: 50;">' +
        '<div ng-click="toggle()" style="font-weight: bold; font-size: 1.1em; margin-bottom: 4px; cursor: pointer; user-select: none;">Grit &#9652;</div>' +
        '<div ng-if="!state.active" style="opacity: 0.7; margin-bottom: 4px;">Not active on this vehicle (yet)</div>' +
        '<div ng-repeat="t in toggles" ng-click="flip(t.key)" style="display: flex; align-items: center; margin: 5px 0; cursor: pointer; user-select: none;">' +
          '<span ng-style="boxStyle(s[t.key])" style="display: inline-block; width: 14px; height: 14px; margin-right: 8px; border: 2px solid #ccc; box-sizing: border-box; border-radius: 2px;"></span>{{ t.label }}</div>' +
        '<div style="margin-top: 6px;">Dirt strength: {{ s.dirtStrength | number:2 }}</div>' +
        '<md-slider aria-label="_" min="0.25" max="2" step="0.05" ng-model="s.dirtStrength" ng-change="setNum(\'dirtStrength\')" style="margin: 0 6px;"></md-slider>' +
        '<div>Drying speed: {{ s.dryingSpeed | number:2 }}</div>' +
        '<md-slider aria-label="_" min="0.25" max="4" step="0.05" ng-model="s.dryingSpeed" ng-change="setNum(\'dryingSpeed\')" style="margin: 0 6px;"></md-slider>' +
        '<div style="display: flex; margin-top: 6px;">' +
          '<md-button flex class="md-raised" md-no-ink style="margin: 2px; min-width: 0;" ng-click="wash()">Wash</md-button>' +
          '<md-button flex class="md-raised" md-no-ink style="margin: 2px; min-width: 0;" ng-click="clearAll()">Clear all</md-button>' +
        '</div>' +
        '<div style="opacity: 0.7; font-size: 0.85em; margin-top: 4px;" ng-if="state.active">Layers: {{ state.layers }} / {{ state.maxLayers }}</div>' +
        '</div>' +
      '</div>',
    replace: true,
    link: function (scope, element) {
      scope.s = {}
      scope.state = {}

      // Zustand auf/zu pro Spieler merken (nur Bequemlichkeit, ohne Speicher einfach zu)
      var KEY = 'grit.app.open'
      scope.open = false
      try { scope.open = localStorage.getItem(KEY) === '1' } catch (e) {}
      // offenes Fenster an die Kopfzeile setzen, unten am Bildschirm nach oben ausweichen
      var PANEL_H = 330
      scope.panelStyle = {}
      var place = function () {
        var r = element[0].getBoundingClientRect()
        var top = Math.max(0, Math.min(r.top, window.innerHeight - PANEL_H))
        var left = Math.max(0, Math.min(r.left, window.innerWidth - 280))
        scope.panelStyle = { top: top + 'px', left: left + 'px' }
      }
      scope.toggle = function () {
        scope.open = !scope.open
        if (scope.open) place()
        try { localStorage.setItem(KEY, scope.open ? '1' : '0') } catch (e) {}
        if (scope.open) refresh()
      }

      var refresh = function () {
        bngApi.engineLua('grit_main and grit_main.uiState()', function (data) {
          scope.$evalAsync(function () {
            if (!data) { scope.state = { active: false }; return }
            scope.state = data
            // Regler nicht überschreiben, während gezogen wird
            angular.forEach(data.settings, function (v, k) { if (!pending[k]) scope.s[k] = v })
          })
        })
      }

      scope.toggles = [{ key: 'dirt', label: 'Dirt' }, { key: 'scratches', label: 'Scratches' }, { key: 'cracks', label: 'Cracks' }]
      scope.boxStyle = function (on) { return on ? { background: '#ff6600', 'border-color': '#ff6600' } : {} }
      scope.flip = function (key) { scope.s[key] = !scope.s[key]; scope.setBool(key) }
      scope.setBool = function (key) {
        bngApi.engineLua('grit_main.set("' + key + '", ' + (scope.s[key] ? 'true' : 'false') + ')')
      }

      // Regler: erst nach 300 ms Ruhe setzen (jedes set schreibt settings/grit.json)
      var pending = {}
      scope.setNum = function (key) {
        if (pending[key]) $timeout.cancel(pending[key])
        pending[key] = $timeout(function () {
          delete pending[key]
          bngApi.engineLua('grit_main.set("' + key + '", ' + Number(scope.s[key]) + ')')
        }, 300)
      }

      scope.wash = function () { bngApi.engineLua('grit_main.washNow()'); $timeout(refresh, 500) }
      scope.clearAll = function () { bngApi.engineLua('grit_main.clear()'); $timeout(refresh, 500) }

      refresh()
      if (scope.open) $timeout(place, 200)   // erst nach dem Einhängen hat die App ihre Lage
      var timer = setInterval(function () { if (scope.open) { scope.$evalAsync(place); refresh() } }, 2000)   // Ebenen-Anzeige, nur wenn offen
      scope.$on('$destroy', function () {
        clearInterval(timer)
        angular.forEach(pending, function (p) { $timeout.cancel(p) })
      })
    }
  }
}])
