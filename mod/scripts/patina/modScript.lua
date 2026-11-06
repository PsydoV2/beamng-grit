-- Patina: lädt die GE-Extension beim Spielstart.
-- Muster: core/modmanager.lua:719-746 (modScript.lua unter /scripts/, setExtensionUnloadMode "manual").
setExtensionUnloadMode("patina_main", "manual")
extensions.load("patina_main")
