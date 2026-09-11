## What it never does

No file is moved, renamed, or deleted, and file contents are never read. The app
requests no Full Disk Access, no Screen Recording, no Input Monitoring, no
camera, no microphone, no contacts, no calendars, and no location.

## Install

Download `RankAndFolder-VERSION.dmg` below, open it, and drag **Rank & Folder**
onto the Applications shortcut beside it.

A zip is published alongside it for anyone scripting the download, with
`SHA256SUMS.txt` beside both.

Open the app from Applications rather than from the disk image. macOS grants
Accessibility permission to one copy at a specific location, so a copy run from
elsewhere is treated as a different program.

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

## About the app

What Rank & Folder does and how it works are described in the [README](https://github.com/drabhikroy/rank-and-folder#readme). Every
release is listed in the
[changelog](https://github.com/drabhikroy/rank-and-folder/blob/main/CHANGELOG.md).
