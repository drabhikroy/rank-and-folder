# Interface design

Rank & Folder is designed for people who want different folders organized differently without learning Finder terminology or configuring a model first.

## Design principles

### Show one decision at a time

Home offers two clear starting points: organize a folder or set up an optional local model. The folder editor separates folder scope from organization, then shows one of Sections, Item Order, or Preview at a time. Model setup follows three visible steps.

### Keep the common path first

Manual organization appears before the optional model path. Adding a folder is the primary action on Home and after model setup. Optional settings are available without competing with the current task.

### Use plain terms

- **Sections** means headings that divide items into groups.
- **Item order** means what appears first inside the smallest section.
- **Use this layout in subfolders** means verified folders below can use the same recipe.
- **Leave this folder and its subfolders alone** means the branch receives no automatic recipe.

Finder's Group By and Sort By names appear only when their exact terminology helps explain compatibility.

### Preserve user control

Previews are read-only. Model results remain proposals. Finder automation is optional. Removing a profile or resetting the app requires a clear review of what will change.

### Make the whole control clickable

Cards, tabs, disclosure rows, and custom buttons use a full content shape. Icon-only controls include labels and Help text. Visual boundaries match their hit regions.

## Visual system

The palette uses jade for ordinary actions, coral and plum for the optional model path, and amber for attention. Status never depends on color alone; every state also uses a word and symbol.

Primary headings use rounded system typography. Body text uses semantic macOS styles through `rankFolderFont`, which lets Standard, Larger, and Largest settings change typography at layout time without scaling button hit regions.

Cards use shared surfaces, corner radii, borders, and spacing. A page should have one dominant action and no more decoration than needed to establish hierarchy.

## Windows and navigation

Quick Tour, Help, Settings, Reset, Models, comparison, preview, model results, and download review are ordinary macOS windows. They can move, resize, minimize, and sit beside the main app. Each defines a practical minimum size.

The main toolbar separates work actions from support actions:

- Add folder and Models
- Settings and Help

The sidebar groups saved folders by location, supports search, and provides familiar add and remove controls. Destructive actions name the affected saved folder and state that files remain untouched.

## Accessibility

The interface supports selectable text, keyboard focus, VoiceOver labels, Reduce Motion, increased contrast, System/Light/Dark appearances, three text sizes, and National Eye Institute color-vision categories.

Important checks include:

- every custom control has a full hit target;
- dynamic button titles keep stable visual and clickable bounds;
- layouts remain readable at minimum size and with Largest text;
- information does not disappear in monochrome or color-vision modes;
- progress, success, warning, and failure use both words and symbols;
- changing appearance updates every open window.

### Color

The interface fills with a fixed set of colors rather than the system accent.
The system accent is chosen in System Settings and can be a light hue such as
yellow, which would drop a white label below the AA body ratio wherever the app
fills a control with it.

The color vision choice selects the whole set, not only the status colors. This
matters because the two most prominent buttons on the home screen are the
primary action and the local model action. In the standard set those are jade
and coral, and under a dichromacy simulation they separate by 0.221 for
deuteranopia and 0.114 for protanopia, on a scale where roughly 0.28 is the
floor for telling two fills apart. A person with red-green color vision
deficiency could not reliably tell the two apart while the interface used one
fixed set, which is why choosing a mode now repaints the app.

Each set is checked two ways. Every fill clears 4.5 to 1 against white, and
every pair of fills is run through a Vienot dichromacy simulation for the
deficiency the set is meant for.

| Set | Fills | White on the lightest fill | Worst pair after simulation |
| --- | --- | --- | --- |
| Standard | jade, coral, plum | 4.93 | not applicable |
| Red-green | blue, amber, dark navy | 4.55 | 0.285 |
| Blue-yellow | teal, crimson, dark maroon | 5.94 | 0.434 |
| Complete | three neutrals | 5.54 | separated by lightness only |

Two limits are worth stating plainly. Under tritanopia, warning and danger both
fall in the warm range and separate by lightness rather than by hue. Under
complete deficiency there is no hue at all. In both cases the word and the
symbol beside the color carry the meaning, which is why no status is ever shown
as color alone.

## Model presentation

Models are explicitly optional. The setup page first asks where Ollama runs, then checks the service, then shows supported model cards. Cards in a row share height and state why a model may help specifically with Rank & Folder.

The comparison window fixes the criteria column while model columns scroll. Recommendation and Mac fit are separate ideas: the stable starting choice does not change merely because storage or another transient score changes.

A model result uses two stages. Review explains the proposed recipe and evidence. Preview shows the grouping structure. Saving is available only after preview. Distinct alternatives remain available for the life of the result window.

## Review checklist

Test interface work with:

- no saved folders and a long saved-folder list;
- Standard, Larger, and Largest text;
- System, Light, and Dark appearance changes while several windows are open;
- every color-vision mode;
- minimum and expanded window sizes;
- long folder names and paths;
- VoiceOver, Full Keyboard Access, Reduce Motion, and Increased Contrast;
- tour navigation, closing, reopening, skip, manual, and model branches;
- zero, one, and several recipe levels;
- model service absent, connecting, ready, downloading, failed, and several-model states;
- reset cancellation, review, completion, and repeated reset.

Research and platform guidance can inform a design choice, but they do not replace usability testing with the app's audience. Current references include Apple's Human Interface Guidelines, WCAG 2.2 target-size and focus guidance, the National Eye Institute's color-vision terminology, and work on progressive disclosure and user-paced segmentation. Any claim drawn from a different medium or population should be treated as a hypothesis to test in Rank & Folder.
