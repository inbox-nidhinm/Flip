<img src="Icon/icon.png" width="128" alt="re-Flip">

# re-Flip

Frame-by-frame vector animation for macOS. Draw, connect the lines into shapes,
and export one animated SVG.

## Requirements

macOS 15 (Sequoia) or later. Apple silicon and Intel.

## Install

re-Flip is not signed with an Apple Developer certificate, so macOS will refuse
to open it on the first try and say it is damaged. It is not. The warning means
the app has no paid signature, and the fix is one command.

Build the app:

```bash
./make-app.sh release
```

Move `build/re-Flip.app` to your Applications folder, then clear the quarantine
flag macOS attached to it:

```bash
xattr -dr com.apple.quarantine /Applications/re-Flip.app
```

Open it normally after that. You only do this once per install.

## Shortcuts

Press `⌘/` in the app for the same list.

### Tools

| | |
|---|---|
| Cursor | `V` |
| Brush | `B` |
| Pen | `P` |
| Rectangle | `R` |
| Circle | `O` |
| Change tool in the same slot | Hold the tool |

### Frames

| | |
|---|---|
| Play / pause | `Space` |
| Previous / next frame | `<` `>` |
| New blank frame | `N` |
| Duplicate frame | `⌘D` |
| Move frame left / right | `⇧⌘<` `⇧⌘>` |
| Onion skin | `⇧O` |
| Paste into every frame | `⌥⌘V` |

### Selection

| | |
|---|---|
| Every layer in this frame | `⌘A` |
| Every layer in every frame | `⇧⌘A` |
| The same layer in every frame | `⌥⌘L` |
| Group layers | `⌘G` |
| Ungroup layers | `⌘⌫` |
| Rename the selected layer | `⌘R` |
| Duplicate as you drag it | `⌥` drag |
| Delete the selection, or points | `⌫` |
| Deselect | `Esc` |

### Order

| | |
|---|---|
| Bring layer to front | `]` |
| Send layer to back | `[` |
| Bring forward | `⌘]` |
| Send backward | `⌘[` |

### Drawing

| | |
|---|---|
| Constrain a shape as you draw | `Shift` |
| Lock a resize, or turn by 15° | `Shift` |
| Break a handle's symmetry | `⌥` |
| End the path open | `Return` |

### Canvas

| | |
|---|---|
| Pan | `⌃` drag |
| Zoom, as does a pinch | `⌘` scroll |
| Move an unlocked reference | `⌘` drag |
| Fit to window | `⌘0` |
| Show or hide layers / tools | `⌘1` `⌘2` |
| Show the shortcuts card | `⌘/` |

### File

| | |
|---|---|
| New | `⌘N` |
| Open | `⌘O` |
| Save | `⌘S` |
| Save as | `⇧⌘S` |
| Export animated SVG | `⌘E` |
| Export animated GIF | `⇧⌘E` |

## Dependencies

[Colorful](https://github.com/jaywcjlove/colorful) by Kenny Wang, MIT. Vendored
into `Sources/Flip/Vendor/Colorful` rather than fetched, so the build works
offline. Local changes are listed in `VENDOR.md` beside it.

## License

Unlicense license.
