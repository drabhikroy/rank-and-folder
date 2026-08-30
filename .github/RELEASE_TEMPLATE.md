## What it never does

No file is moved, renamed, or deleted, and file contents are never read. The app
requests no Full Disk Access, no Screen Recording, no Input Monitoring, no
camera, no microphone, no contacts, no calendars, and no location.

## Install

Download `RankAndFolder-VERSION.dmg` below, open it, and drag **Rank & Folder**
onto the Applications shortcut beside it.

A zip is published alongside it for anyone scripting the download.

This build is signed to run on the machine that made it rather than with a paid
Developer ID, so macOS holds it the first time you open it. The warning says
Apple could not verify the file is free of malware. That is what macOS says
about any software it has not seen notarized, including software that is fine.
Check the download against the published checksums first, then allow it.

On macOS 15 and later, including macOS 26, a right-click no longer overrides
this. Six steps, once:

**1. Open the disk image. Choose Done.**

In both this dialog and the one in step 3, **Move to Trash** is the highlighted
button, so pressing Return deletes the download.

<img src="https://raw.githubusercontent.com/drabhikroy/rank-and-folder/main/Docs/images/install-1-not-opened.png" width="372" alt="A macOS dialog headed RankAndFolder-1.0.4.dmg Not Opened, saying Apple could not verify the file is free of malware, with a highlighted Move to Trash button above a Done button.">

**2. Open System Settings, go to Privacy & Security, and scroll to Security. Click Open Anyway.**

<img src="https://raw.githubusercontent.com/drabhikroy/rank-and-folder/main/Docs/images/install-2-open-anyway.png" width="479" alt="The Security section of System Settings Privacy and Security, saying RankAndFolder-1.0.4.dmg was blocked to protect your Mac, with an Open Anyway button beside it.">

**3. Choose Open Anyway again.**

<img src="https://raw.githubusercontent.com/drabhikroy/rank-and-folder/main/Docs/images/install-3-confirm.png" width="372" alt="A macOS dialog asking whether to open RankAndFolder-1.0.4.dmg, with a highlighted Move to Trash button above Open Anyway and Done buttons.">

**4. Authenticate with Touch ID, or choose Use Password.**

<img src="https://raw.githubusercontent.com/drabhikroy/rank-and-folder/main/Docs/images/install-4-authenticate.png" width="372" alt="A Privacy and Security dialog asking for an administrator Touch ID or password, with a Use Password button and a Cancel button.">

**5. Enter an administrator name and password.**

<img src="https://raw.githubusercontent.com/drabhikroy/rank-and-folder/main/Docs/images/install-5-password.png" width="372" alt="A Privacy and Security dialog with fields for an administrator username and password, and Cancel and OK buttons.">

**6. Drag Rank & Folder onto the Applications shortcut.**

<img src="https://raw.githubusercontent.com/drabhikroy/rank-and-folder/main/Docs/images/install-6-drag-to-applications.png" width="712" alt="The mounted Rank and Folder 1.0.4 disk image window, showing the Rank and Folder app icon beside a shortcut to the Applications folder.">

Open the app from Applications rather than from the disk image. macOS grants
Accessibility permission to one copy at a specific location, so a copy run from
elsewhere is treated as a different program. The app inherits the same hold the
disk image had, so the first launch may ask you to repeat steps 2 through 5 for
the app itself.

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
