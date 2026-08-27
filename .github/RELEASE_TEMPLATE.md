Rank & Folder gives each folder you save its own layout, so changing how your
downloads are arranged does not change how your invoices are arranged.

## What is in this release

**Saved layouts.** A layout has two parts. Sections split a folder into
headings, and Item Order decides what comes first inside the smallest section.
Each supports up to seven levels, so you can group by kind, then by date added,
and sort newest first inside that.

**Inheritance with exceptions.** A layout can extend into subfolders, and any
subfolder can be marked as one to leave alone. Where several saved layouts could
apply, the closest one wins, and anything ambiguous stops rather than guessing.

**Finder, driven honestly.** Layouts are applied through the same View Options
controls you would click yourself, using the public Accessibility API. Finder can
reproduce one Section rule and one Item Order rule, so anything deeper is shown
as a read only preview inside the app.

**Optional local suggestions.** Ollama can propose a starting layout, running
entirely on your Mac. The model sees a count summary of the folder, never
filenames or file contents, and every response is validated before it can become
a layout.

**Accessibility.** Four color vision modes audited to WCAG 2.2 AA, a text size
control, and light, dark, or system appearance.

## What it never does

No file is moved, renamed, or deleted, and file contents are never read. The app
requests no Full Disk Access, no Screen Recording, no Input Monitoring, no
camera, no microphone, no contacts, no calendars, and no location.

## Install

Download `RankAndFolder-1.0.0.dmg` below, open it, and drag **Rank & Folder**
onto the Applications shortcut beside it.

A zip is published alongside it for anyone scripting the download.

This build is signed to run on the machine that made it rather than with a paid
Developer ID, so macOS will hold it on first launch. Right-click the app, choose
Open, then confirm. You only do this once.

Applying layouts to Finder needs Accessibility permission, which the app asks for
when you first use it. Everything else works without it.

## Requirements

macOS 14 or later, Apple silicon or Intel.

## Verify the download

`SHA256SUMS.txt` is published with this release. With it in the same folder as
the download:

```sh
shasum -a 256 -c SHA256SUMS.txt
```
