## What it never does

No file is moved, renamed, or deleted, and file contents are never read. The app
requests no Full Disk Access, no Screen Recording, no Input Monitoring, no
camera, no microphone, no contacts, no calendars, and no location.

## Install

Download `RankAndFolder-VERSION.dmg` below, open it, and drag **Rank & Folder**
onto the Applications shortcut beside it.

A zip is published alongside it for anyone scripting the download.

This build is signed to run on the machine that made it rather than with a paid
Developer ID, so macOS holds both the disk image and the app the first time you
open each of them. The message says Apple could not verify the file is free of
malware. That is what macOS says about any software it has not seen notarized,
including software that is fine. Check the download against the published
checksums first, then allow it.

On macOS 15 and later, including macOS 26, Apple no longer accepts a
right-click to override this. Open the file, and when the warning appears
choose **Done**. Then open **System Settings**, go to **Privacy & Security**,
scroll to the **Security** section near the bottom, and click **Open Anyway**
beside the file name. Confirm, and authenticate when asked. Do this within an
hour of seeing the warning, or the button stops offering the file. You repeat
it once for the disk image and once for the app, and then neither asks again.

On macOS 14, right-click the file, choose **Open**, and confirm.

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
