# Changelog

Notable changes to Rank & Folder. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Dates are ISO 8601.

## [1.0.0] - 2026-08-27

First public release.

### Saved layouts

- Every saved folder keeps its own layout. A layout has two parts: Sections,
  which split a folder into headings, and Item Order, which decides what comes
  first inside the smallest section. Each supports up to seven levels.
- Layouts can extend into subfolders, and any subfolder can be marked as an
  exception that is left alone. When several saved layouts could apply, the
  closest one wins, and anything ambiguous stops rather than guessing.
- A saved folder is identified by a bookmark and a filesystem identifier rather
  than by its path text, so a folder deleted and recreated at the same path is
  treated as a different folder.

### Finder

- Layouts are applied by driving the same View Options controls a person would
  click, through the public Accessibility API. No private API and no Finder
  plugin.
- Finder can reproduce one Section rule and one Item Order rule. Anything deeper
  is shown as a read only preview inside the app.
- An optional Finder extension adds a menu item for saved folders.

### Local model

- Optional layout suggestions run on this Mac through Ollama. The app talks only
  to the loopback address and refuses any redirect that leaves it.
- The model receives a count summary of the folder rather than filenames or file
  contents, and every response is checked against a fixed list of criteria
  before it can become a layout.
- A pinned Ollama runtime can be installed into the app's own support folder,
  verified by checksum, separate from any system wide install.

### Interface

- Four color vision modes, all audited to WCAG 2.2 AA.
- Text size control, and light, dark, or system appearance.

### Notes

- The app never moves, renames, or deletes files, and never reads file contents.
- Requires macOS 14 or later.

[1.0.0]: https://github.com/drabhikroy/rank-and-folder/releases/tag/v1.0.0
