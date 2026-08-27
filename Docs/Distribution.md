# Distribution and permissions

## Building the release artifacts

Run:

```sh
./Scripts/build-standalone.sh
```

The script reads the version and build number from `Config/Base.xcconfig` and
writes three files into `dist/`:

| File | Purpose |
| --- | --- |
| `RankAndFolder-<version>.dmg` | What a person downloads. Holds the app beside an Applications shortcut. |
| `RankAndFolder-<version>-macOS.zip` | The same app for anyone scripting a download, with nothing to mount. |
| `SHA256SUMS.txt` | Checksums for both, computed from the exact files that were built. |

It requires Xcode command-line tools and `rsvg-convert` from `librsvg`, which
renders the icon.

### About the disk image

The image carries the app, a symbolic link to `/Applications` as the drag
target, and the app icon as the volume icon.

The window layout, meaning icon size and the position of the two items, is set
by asking Finder. That needs a logged-in desktop session, so the step is skipped
when the script runs on a headless build machine. The image is valid either way
and only the opened window looks plainer, which is why the release workflow does
not fail on it.

The image is created with roughly fifty megabytes of slack. `hdiutil` otherwise
sizes an image to fit its contents exactly, leaving Finder no room to record the
layout it was asked for, and that write fails without reporting anything.

### About the signature

Both the app and the disk image get an ad-hoc signature. That proves neither has
been altered since it was built. It is not a Developer ID signature and the
result is not notarized, so Gatekeeper holds the app on first launch and the
person has to open it once through the context menu.

## Public release checklist

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig`.
2. Confirm bundle identifiers, App Group, deployment target, entitlements, and signing team.
3. Run the core test suite and a warnings-as-errors app build.
4. Perform the manual checks in `Docs/Security-Review.md`.
5. Archive with the intended Developer ID Application certificate.
6. Verify the app and optional extension signatures, designated requirements, Hardened Runtime, and entitlements.
7. Submit the exact artifact for notarization and wait for acceptance.
8. Staple the ticket to the app, and to the disk image, then run a Gatekeeper assessment on a clean Mac account.
9. Package the stapled app without resource-fork or quarantine metadata.
10. Publish `SHA256SUMS.txt` and verify a fresh download against it.
11. Confirm the GitHub release carries the PolyForm Noncommercial License notice and links to `PRIVACY.md` and `SECURITY.md`.

Do not copy a checksum from an earlier build. The script computes them from the
files it just produced, and a download is checked against that file rather than
against a pasted value:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Entitlement sets

The containing app uses Hardened Runtime and is not sandboxed because it optionally controls Finder through Accessibility. The Finder Sync extension is sandboxed and uses the configured App Group. The standalone development package omits the extension and App Group dependency.

Inspect built entitlements rather than relying on project settings alone:

```sh
codesign -d --entitlements :- /Applications/Rank & Folder.app
codesign -d --entitlements :- "/Applications/Rank & Folder.app/Contents/PlugIns/Rank & Folder Finder Extension.appex"
```

## User permissions

- **Files and Folders:** granted case by case through the standard folder picker.
- **Accessibility:** optional and used only for Finder automation.
- **Local Network:** may appear for the optional Ollama loopback connection.

Rank & Folder does not require Full Disk Access, Screen Recording, Input Monitoring, camera, microphone, contacts, calendars, or location. The Finder Sync extension is optional.

## Development-build permission identity

Replacing an ad-hoc-signed build can make macOS treat it as a different Accessibility client. If the app shows permission as missing, remove the existing Rank & Folder entry, add the exact copy being run, and reopen the app. Public Developer ID releases should maintain one signing identity across updates.
