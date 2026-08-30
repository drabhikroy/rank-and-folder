# Changelog

Notable changes to Rank & Folder. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Dates are ISO 8601.

## [1.0.4] - 2026-08-30

### Fixed

- The managed Ollama runtime failed to install. The check added in 1.0.3 read
  the code directory hash from a codesign description printed at a verbosity
  that does not include it, so a correct install was reported as a program
  macOS could not verify. The description is now requested at the verbosity
  that prints the line, and the line it looks for is parsed in one place beside
  the flags that produce it.
- A verified install is no longer discarded when its identity cannot be
  recorded. Recording the hash sat inside the same block as signature
  verification, so a failure to record deleted an archive that had already
  passed its checksum and its signature check. Recording is now separate, and a
  failure leaves the install in place. The next launch then adopts the program
  it finds, as it does for a runtime installed before pinning existed.

## [1.0.3] - 2026-08-30

### Security

- The managed Ollama runtime now has to be the same program that was installed.
  Rank & Folder records the code directory hash of the executable at install
  time, when it is known to have come from the archive whose SHA-256 was
  checked, and requires that hash again before every later launch. Signature
  verification on its own shows only that a program is unchanged since it was
  signed, so a replacement written into the support folder and signed again
  would have passed. A runtime installed by an earlier version has no recorded
  hash and adopts its current one on first launch. Removing and reinstalling
  the runtime from the Models window records a hash tied to a verified archive.
- The managed runtime is started with a fixed environment rather than a copy of
  the environment Rank & Folder was launched with. Ollama reads more than a
  dozen `OLLAMA_` variables, so an inherited environment could have moved the
  model directory or widened the origins the local server accepts without the
  person choosing either. The child now receives only the loopback host and
  origin, the private model directory, cloud mode off, `PATH`, `HOME`, and
  `TMPDIR`.
- A saved folder is recognized only when every stored fact about it agrees. A
  bookmark can resolve by path after the folder it was made from is gone, so a
  folder deleted and recreated at the same path could satisfy the bookmark
  alone. When a record carries both a bookmark and a recorded filesystem
  identifier, both are now checked.
- Saved layouts and leave-alone exceptions read back from shared storage must
  name an absolute path. The preference file they live in is writable by other
  processes on the Mac, and a relative path would have been resolved against
  whatever the working directory happened to be.
- Finder automation confirms that the application it drives is the Finder macOS
  ships, at its system path, rather than trusting any running program that
  carries Finder's bundle identifier.
- The archive safety checks no longer skip hidden entries, so a hidden symbolic
  link pointing outside the staging folder is caught rather than ignored.
- Explanatory text written by a local model is stripped of control characters
  and text direction overrides before it is shown, so model prose cannot change
  how the wording around it is drawn.
- The download host allowlist is defined once instead of twice. Two copies can
  drift, and the copy that is missed is the one deciding where a download may
  come from.
- Continuous integration runs with read-only permissions, and both workflows
  pin their actions to reviewed commits rather than moving version tags.

## [1.0.2] - 2026-08-28

### Changed

- The local model card fills its button with red again. It was changed to plum
  in 1.0.1 on the reasoning that red reads as destructive, but plum sits close
  to the window background in dark appearance and was harder to see. The red is
  now a deeper brick rather than the shade the app reports failures in, so an
  optional setup step and an error no longer look alike. The status colors have
  their own values and are not affected.

## [1.0.1] - 2026-08-27

### Fixed

- The color vision choice now selects the colors the whole interface fills
  with, not only the four status colors. It previously changed status
  indicators alone, so the two most prominent buttons on the home screen stayed
  jade and coral in every mode. Those two separate by 0.221 under a
  deuteranopia simulation and 0.114 under protanopia, close enough that a
  person with red-green color vision deficiency could not reliably tell them
  apart. The red-green and blue-yellow sets have been rebuilt around pairs that
  survive their own simulation, and every fill clears 4.5 to 1 against white.
- In the complete color vision deficiency mode, a filled status circle used the
  primary label color while its symbol stayed white, so the symbol disappeared
  in dark appearance. Filled status surfaces now use a label color that inverts
  with the appearance.
- The paired toolbar buttons used a material that samples the window behind it
  and rendered as a grey slab in light appearance. They now use the control
  background color.
- Two card outlines were white at low opacity and were invisible against a
  light background. The home screen introduction has been rebuilt so its wash
  sits over an opaque card rather than tinting one.
- The add and remove controls at the foot of the sidebar showed a symbol and a
  word each with no separation, so the row read as one phrase. They are now a
  grouped pair of symbol buttons, with the words on the tooltip and the
  accessibility label.
- The local model card filled its button with the danger color. An optional
  setup step no longer looks destructive.
- The application menu title came from the target name and read
  RankAndFolder. It now reads Rank & Folder, and nine strings that referred to
  the app by its internal name have been corrected.
- The Hide and Quit menu items in the standalone build read
  $(PRODUCT_DISPLAY_NAME). The build script copies the standalone property list
  without expanding build variables, so the display name is now written out in
  full. This affected 1.0.0 as well.
- In the complete color vision deficiency mode, the colors were fixed dark
  neutrals. A set that carries no hue can only separate by lightness, so
  anywhere one was used as a symbol or a label rather than as a fill it
  disappeared against a dark window. Those colors now follow the appearance,
  and the label on a filled surface inverts with them.
- The Hide and Quit menu items in the standalone build read
  $(PRODUCT_DISPLAY_NAME). The build script copies the standalone property list
  without expanding build variables, so the display name is now written out in
  full. This affected 1.0.0 as well.
- In the complete color vision deficiency mode, the colors were fixed dark
  neutrals. A set that carries no hue can only separate by lightness, so
  anywhere one was used as a symbol or a label rather than as a fill it
  disappeared against a dark window. Those colors now follow the appearance,
  and the label on a filled surface inverts with them.

### Changed

- The Appearance settings preview shows the fills as well as the status colors,
  so a mode can be judged from the colors themselves.
- Every type in the source carries a comment saying what it is for.

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

[1.0.2]: https://github.com/drabhikroy/rank-and-folder/releases/tag/v1.0.2
[1.0.1]: https://github.com/drabhikroy/rank-and-folder/releases/tag/v1.0.1
[1.0.0]: https://github.com/drabhikroy/rank-and-folder/releases/tag/v1.0.0
