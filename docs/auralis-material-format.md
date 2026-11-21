# Custom Auralis materials

In Settings → Appearance → Surface material, choose **Export editable material**. Open the exported JSON file in a text editor, change its name and settings, save it, and choose **Import material**. Importing a material with the same name replaces your previous custom material with that name. The currently selected custom material can also be removed.

```json
{
  "format": "auralis-material",
  "version": 1,
  "name": "My satin glass",
  "finish": "satin",
  "controls": "soft",
  "translucency": 50,
  "shading": 65,
  "layout": "standard",
  "text": "crisp"
}
```

Finish is `matte`, `satin`, `gloss`, `frosted`, or `clear`. Controls are `rounded`, `soft`, or `angular`. Optional layout is `compact`, `standard`, or `spacious`; optional text is `crisp` or `soft`. Translucency and shading are numbers from 0 to 100. A higher translucency makes the surface more see-through; shading controls the highlight strength. Material files contain data only, not CSS, scripts, textures or external resources. Color themes and indicator styles remain separate. The selected finish also determines the Windows backdrop effect for see-through desktop backgrounds: frosted uses acrylic, satin and gloss use blur, and matte and clear do not request a Windows blur effect. Availability and the blur strength depend on Windows. Wallpaper blur is controlled separately.

Exporting Frosted Layers provides an editable approximation rather than the original animated multilayer shader. Custom materials are included in Auralis preferences backups.
