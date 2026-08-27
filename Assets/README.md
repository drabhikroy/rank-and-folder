# Assets

Every icon in Rank & Folder is drawn as SVG and rendered at build time. Nothing
here is a bitmap, so the artwork stays editable and every size is generated
from the same source.

## Files

| File | Purpose |
| --- | --- |
| `AppIcon.svg` | The full app icon. Rendered at 128, 256, 512, and 1024 pixels. |
| `AppIcon-Small.svg` | The same mark simplified for 16 and 32 points. |
| `MenuBarIcon.svg` | A single color template image for the menu bar item. |

## What the icon shows

A folder holding an outline tree. A heading branches into smaller headings, and
the items under a heading run longest to shortest.

That is a recipe drawn as the app defines it. Sections create headings and nest
inside one another up to seven levels. Item order decides what comes first
inside the smallest section, which is why the leaves descend in length. Two
parts doing two different jobs.

The branch lines are the reason this mark works. An indented list only implies
which heading a row belongs to and leaves the eye to infer it. A drawn line
states it. Depth is the reason the app exists, since Finder groups a folder one
level deep and sorts it one level deep, so the mark makes depth explicit rather
than hinting at it.

## Color

| Role | Value |
| --- | --- |
| Field | `#0E1210` |
| Folder | Sand, `#D6BA9A` |
| First level heading | Jade, `#095F54` |
| Second level heading | Plum, `#633375` |
| Items | Coral, `#B02F3B` |
| Branch lines | Slate, `#4C5661` |

Every element clears the WCAG 2.2 ratio of 3 to 1 against the folder, at 4.09,
5.02, 3.42, and 4.04 to 1. The folder reads against the field at 10.20 to 1.

The sand folder is lighter than the values the bars were first tuned against, so
three of them were darkened to keep their footing. Coral is the constraint every
time. At its original `#C93D47` it measures 2.68 to 1 on the sand and fails, so
it moved to `#B02F3B`.

`amber` is the one palette member the icon does not use. It fails against the
jade bar and cannot be a bar on any folder light enough to carry the other three.

## Surface treatment

Every shape is a flat matte fill. No gradients, no shadows, no rim lights. A
draft that shaded each shape with a gradient and a light along its top edge read
as brushed metal and pulled attention from the idea underneath.

macOS 26 renders app icons from layered artwork and supplies material, shadow,
specular highlight, and enclosure shape itself, so artwork on that path should
carry none of its own. These files carry none. The rounded square here serves
only the icns that `Scripts/build-standalone.sh` produces for macOS 14 and later.

## Why there are two app icon files

At and below 32 points the wider tree closes up and the rows merge.
`AppIcon-Small.svg` reduces to one heading, one heading inside it, and one item,
with thicker bars and branch lines, so three levels still step visibly at Finder
list and menu sizes.

## Light and dark appearance

Three different answers, depending on which surface and which macOS.

**Menu bar: yes, automatically.** `MenuBarIcon.svg` is a template image, so macOS
recolors it for a light menu bar, a dark menu bar, and the highlighted state.
Nothing else is needed once it is wired to an asset catalog.

**App icon on macOS 14 and 15: no, and it cannot.** The icns format that
`Scripts/build-standalone.sh` produces holds one appearance. The Dock icon looks
the same in Light and Dark. This is a platform limit rather than something left
undone, so the default artwork is drawn to sit well on both, with a dark field
that holds against a light desktop and a light folder that holds against a dark
one.

**App icon on macOS 26: yes, through Icon Composer.** macOS 26 renders an app
icon in Default, Dark, Clear Light, Clear Dark, Tinted Light, and Tinted Dark.
Those come from a layered `.icon` file, which Xcode 26 compiles into `Assets.car`
while also emitting a backwards compatible icns for older systems. The project
does not use that path yet. These files are the source for it when it does:

| File | Feeds |
| --- | --- |
| `AppIcon.svg` | Default |
| `AppIcon-Dark.svg` | Dark |
| `AppIcon-Mono.svg` | Clear and Tinted, in both their light and dark forms |

### What the variants change, and why

The dark variant keeps the structure. The mark already puts a light folder on a
dark field, so it is a dark-mode design to begin with. The field deepens and the
folder steps down the same warm ramp, from `#D6BA9A` to `#CBB294`, so it does not
glare in a dark room.

That stop was set by measurement rather than by eye. Two darker stops were tried
first and both failed: at `#BFA487` coral falls to 2.68 to 1 and at `#C6AC90` it
is still 2.93. `#CBB294` is the first value where every bar holds, coral at 3.12
to 1.

The monochrome variant is the one that needed real rework. A single tint
collapses every hue to one color, so jade, plum, and coral would merge and the
three levels would disappear. The levels step by brightness instead. This works
only because depth is carried by indentation and by the branch lines rather than
by hue, which is the same property that makes the default artwork survive a
grayscale check.

Layer order for Icon Composer, background first: field, folder, branch lines,
section headings, items. Nothing carries a baked shadow or gradient, so the
system supplies its own material and specular highlight.

## Menu bar

`MenuBarIcon.svg` is a template image. macOS recolors template images for light
and dark menu bars, so every shape is opaque black and the file carries no color
of its own. Using it requires an image set in an asset catalog marked as a
template, which the project does not have yet. The menu bar item currently uses
the `folder.badge.gearshape` system symbol.

The menu bar mark shows no tree. At 36 points in one color the branch lines and
the bars merge, so it falls back to a folder holding two grouped rows.

## Rebuilding

`Scripts/build-standalone.sh` renders the iconset and calls `iconutil`. It needs
librsvg:

```sh
brew install librsvg
```

To preview a single size without running the whole build:

```sh
rsvg-convert -w 512 -h 512 Assets/AppIcon.svg -o /tmp/preview.png
```
