# Security and code review

Reviewed: August 26, 2026

Scope: Rank & Folder 1.0.0 source, shared core tests, Finder Sync extension, build configuration, packaging script, privacy documentation, and security documentation.

## Result

The reviewed source builds successfully with Swift and C-family warnings treated as errors. The shared core test suite passes. No code path was found that reads file contents, edits `.DS_Store`, requests Full Disk Access, records the screen, captures global keyboard input, sends telemetry, stores cloud credentials, or lets a model execute tools.

The review corrected several defects:

- the managed Ollama directory now includes the pinned runtime version instead of storing interpolation text literally;
- installations made with the alternate directory name remain discoverable and removable;
- the managed Ollama executable's macOS signature is checked before every launch, not only after extraction;
- cancellation is forwarded into archive installation and checked before a staged runtime becomes active;
- Accessibility values are type-checked before conversion to `AXUIElement`;
- Finder errors no longer contain a stale app version;
- reopening the app prefers the main Rank & Folder window instead of whichever utility window happens to be first;
- future file dates no longer count as recently modified;
- equal category counts now have a stable alphabetical order in model prompts;
- unused provider routes and interface fragments were removed so the implementation matches the local-model or manual choices shown to users;
- standalone package names and property-list versions now come from the central build configuration.

## Trust boundaries

### Selected folders

Rank & Folder receives folder access through the standard macOS folder picker. Metadata views require a current identity match. Descendant use requires a verified filesystem relationship, matching live volume, and compatible File Provider classification. Lexical path matching does not grant authority.

Residual risk: filesystem and provider APIs can fail or become unavailable. Rank & Folder responds by refusing metadata or inherited use. Manual tests remain important for iCloud Drive, third-party File Provider folders, network volumes, removable volumes, moved folders, and replaced folders.

### Finder Accessibility

The Accessibility adapter targets Finder's fixed bundle identifier, requires active Finder, verifies the focused folder, searches bounded interface trees, and acts only on Finder view controls. A failed location or control check stops the change.

Residual risk: Accessibility is a broad macOS permission, Finder's interface is not a semantic sorting API, and localized or redesigned controls may stop working. Release testing must cover supported macOS versions, Finder views, toolbar customization, and advertised languages. Users can revoke Accessibility at any time without losing the editor or preview.

### Finder Sync extension

The extension passes a Finder target to the containing app. It does not resolve recipe ancestry, read folder contents, or automate Finder. The app performs fresh profile, boundary, identity, and relationship checks.

Residual risk: extension state and App Group configuration depend on the exact signed build. Both extension-on and standalone artifacts need separate release verification.

### Local Ollama service

The client is fixed to `127.0.0.1:11434`, disables caches, cookies, and proxy settings, rejects redirects, bounds responses, and restricts model identifiers to the catalog. Folder summaries exclude filenames, paths, tag text, file contents, and individual records.

Residual risk: any local process can attempt to bind the loopback port, and an existing Ollama installation controls its own model storage and network activity. The app validates endpoint shape and response limits but does not authenticate the local service. The interface identifies the local boundary and requires review before saving a model result.

### Managed Ollama download

The installer uses a fixed HTTPS release URL, a narrow redirect-host list, a pinned SHA-256 checksum, archive path and symlink checks, an item-count limit, a staging directory, macOS signature verification, fixed executable arguments, and a Rank & Folder-owned models directory. Signature verification is repeated before launch.

Residual risk: Ollama is third-party executable code. A public release should independently verify the official archive and checksum, record the verification, and review upstream changes before updating the pin. Cancellation and removal should be exercised with a slow or interrupted download on a test account.

### Model output

Model output is untrusted. The parser limits response size, requires JSON, recognizes a fixed vocabulary, caps generated rule counts, removes duplicates, validates directions, filters explanation text, and requires user approval.

Residual risk: a valid but unhelpful recipe can still be proposed. The app labels results as editable ideas and keeps final control with the user.

### Persistence and reset

Profiles and boundaries decode as one configuration. A malformed boundary store prevents profiles from becoming active. Reset closes its window before changing appearance and state, then returns Quick Tour to its first page. Runtime and model removal are separate opt-in choices.

Residual risk: `UserDefaults` is not an encrypted database and should never receive secrets or sensitive folder summaries. Current saved data is described in `PRIVACY.md`.

## Verification performed

- Swift Package core tests
- Complete Debug Xcode build with signing disabled
- Swift and C-family warnings treated as errors
- Source scan for force casts, forced unwraps, shell execution, networking, sensitive APIs, stale version strings, generated-history comments, and dead provider routes
- Review of profile persistence, identity checks, descendant resolution, request queueing, Finder verification, preview enumeration, model validation, runtime installation, reset, and packaging

## Manual release checks still required

Automated tests cannot prove Finder UI behavior, macOS permission prompts, signing identity, notarization, or visual layout. Before publishing a release, test:

1. a clean macOS account with no Rank & Folder permissions;
2. Accessibility grant, revoke, replacement build, and re-grant;
3. Finder list, icon, column, and gallery views where supported;
4. local, iCloud Drive, supported third-party File Provider, removable, network, moved, and replaced folders;
5. exact recipes, inherited recipes, branch exceptions, paused profiles, and rich preview-only recipes;
6. existing Ollama, Rank & Folder-managed Ollama, multiple models, download cancellation, removal, invalid output, and service loss;
7. Light, Dark, System switching, all text sizes, all color-vision modes, VoiceOver, keyboard navigation, Reduce Motion, and window resizing;
8. reset review and repeated reset;
9. Developer ID signature, entitlements, notarization acceptance, stapling, Gatekeeper launch, ZIP checksum, and extension state for the exact artifact.

## Assurance

This review provides evidence about the inspected source and tests. It is not proof that the app is completely safe or defect-free. Release artifacts, dependencies, signing, the toolchain, macOS, Finder, and Ollama add risks outside the source review and must be checked separately.
