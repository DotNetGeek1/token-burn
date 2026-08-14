# Web export

Godot writes the HTML5 playtest here as `index.html` plus the matching `.js`,
`.wasm` and `.pck` files.

The Play page iframes `/game/index.html`. Binaries are gitignored — export before
a local preview, and the site deploy workflow exports them on CI:

```powershell
./tools/export_web.ps1
```
