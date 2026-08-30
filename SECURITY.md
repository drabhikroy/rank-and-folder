# Security policy

## Honest assurance

No application can be promised **100% safe**. Source review, tests, signatures, checksums, notarization, and independent review can reduce risk and provide evidence; they cannot prove the absence of every defect, compromised dependency, toolchain problem, operating-system vulnerability, or future exploit.

Rank & Folder 1.0.0 is intentionally inspectable. The reviewed source contains no telemetry, analytics, advertising, automatic updater, login-item installer, arbitrary command field, shell-script execution, global keyboard monitor, clipboard reader, screen capture, camera or microphone access, cloud API client, cloud credential store, or file-content reader. It does not read or edit `.DS_Store` directly; Finder may save its own view preference after Rank & Folder operates Finder’s supported controls.

The optional managed-model path does launch fixed processes: `/usr/bin/tar` to list and extract a checksum-pinned archive, `/usr/bin/codesign` to verify and identify its extracted executable, and that verified Ollama executable with the single argument `serve`. No filename, folder item, model output, prompt, preference value, or user-entered string becomes an executable path or argument in those calls.

The app can write fixed official Ollama install/start commands or a pull command containing one vetted catalog model identifier to the clipboard only after the user chooses **Copy**. It never executes those commands and does not inspect existing clipboard contents.

## Accessibility permission

macOS Accessibility permission is broad. A malicious app with this permission could control other applications. Rank & Folder’s implementation is isolated in `App/FinderAccessibilityClient.swift` and limited to:

1. locating Finder by its fixed bundle identifier, `com.apple.finder`;
2. reading the focused or main Finder window’s `AXDocument`, `AXURL`, or standard title-bar document proxy to identify its folder;
3. inspecting accessibility roles, titles, and children within Finder’s relevant toolbar, View menu, and View Options window;
4. choosing Finder’s existing section and item-order controls when the saved recipe can be represented exactly.

Rank & Folder does not collect keystrokes, install a global input monitor, inspect unrelated application interfaces, take screenshots, or use Accessibility to read file contents.

The adapter verifies the active application and expected folder before changing a control and fails closed when permission is denied, Finder is inactive, the location cannot be verified, or an expected control is absent. If Finder omits its location attributes for a cloud folder, passive automation stays off. The user-initiated **Open in Finder and Apply** fallback requires a successful `NSWorkspace` open in Finder, active Finder, an exact title match, and an authorization that expires after five seconds. This fallback is a narrow best-effort check, not a cryptographic identity proof: two same-named folders and a focus race remain a residual risk when Finder exposes no URL.

Accessibility is not needed for Folder preview, recipe editing, Models, model requests, or the Mac compatibility check. Revoke it under **System Settings > Privacy & Security > Accessibility** to stop Finder observation and control; the rest of the app remains usable.

## File and metadata access

`AdvancedFolderLoader` and `FolderSnapshotBuilder` use public Foundation and Uniform Type Identifiers APIs. They enumerate only the immediate visible children of a selected, saved folder and read standard URL metadata. They do not recursively walk subfolders, read file data, change permissions, move or rename items, delete anything, or modify filesystem metadata.

Folder preview uses names and metadata for its read-only display. Local models receive only aggregate counts and ranges; model prompts exclude filenames, paths, file contents, tag values, and individual item records.

Open and Show actions are handed to `NSWorkspace` and Finder. Removing a Rank & Folder profile deletes only the saved recipe after confirmation, not the folder or its contents.

## Folder inheritance and identity checks

Schema v4 can mark a saved recipe **Use this layout in subfolders**. Resolution remains fail-closed and keeps two values separate:

- the **source profile** supplies the saved recipe and revision;
- the **target folder** is the folder Finder verifies, opens, suppresses, or displays in Folder preview.

An active exact saved choice wins. Otherwise, the closest verified saved choice above the target that includes subfolders is considered. An explicit **leave this branch alone** boundary, a paused profile, a replaced or unavailable record, or duplicate/ambiguous records blocks choices farther above. An active exact-only profile above the target is transparent. A richer closest recipe is not skipped in favor of a simpler farther recipe.

Profiles and boundaries are decoded as one configuration. If boundary data is malformed or corrupt, `ProfileStore` publishes neither collection and no profile is eligible for use. This prevents a partially loaded configuration from failing open across a boundary that may have been lost during decoding.

New or explicitly refreshed records use regular bookmarks created with `.withoutImplicitSecurityScope`. They are resolved with `.withoutUI`, `.withoutMounting`, and `.withoutImplicitStartAccessing`; Rank & Folder does not treat them as access grants. The production checker requires a live non-package directory, rejects non-file and remote-host URLs, resolves symlinks, verifies that the bookmark still identifies the saved path, uses `FileManager.getRelationship`, and requires the same live volume. Descendant use also requires both locations to be positively local or in the same File Provider domain. An unknown provider result may preserve verified exact behavior but cannot authorize a descendant.

Lexical path components never authorize descendant use. They may only stop a broken or path-only record from allowing a farther rule. A path-only schema profile can remain available for exact Finder automation, but Folder preview and model requests reject it before enumerating metadata. The user must remove and add that folder again to capture the identity required by those metadata paths. Such records cannot authorize descendants silently.

Turning on subfolder use does not recursively enumerate the tree. Resolution occurs only for the target currently opened or explicitly previewed. Folder preview then enumerates only that target’s immediate visible children.

Adding a saved folder or leave-alone boundary can await filesystem relationship checks. The main-actor store repeats its exact-profile and exact-boundary duplicate checks immediately before mutation so two windows cannot create conflicting records while an earlier check is suspended.

## Model safety boundaries

The current interface offers Ollama as its model path. Ollama receives a narrow classification prompt with a fixed criterion vocabulary. A generated recipe is parsed as JSON, restricted to supported criteria and directions, capped at three model-created levels in each area, deduplicated, normalized, and given a safe Name-order fallback. Unrecognized and duplicate fields are discarded; missing or unsupported directions use the safe default. Unusable documents are rejected. The explanation is length-limited, and a proposed layout is never saved until the user chooses to use it.

Choosing no model means Rank & Folder does not generate a layout. If the selected Ollama service or model is unavailable, the request reports an error instead of silently substituting a different method. Rank & Folder does not give a model tools, file handles, shell access, or permission to apply a result on its own.

## Network and managed-runtime boundary

The current source has two narrow optional network paths. The Ollama API connector is fixed to `http://127.0.0.1:11434/api/`. It can:

- check the local Ollama version and installed-model list;
- submit the aggregate folder summary for generation;
- ask Ollama to pull one of the supported catalog’s model identifiers and read progress events; and
- after a named confirmation, ask Ollama to delete one recognized model identifier.

While the local-model path is selected, the version and installed-model check repeats every two seconds so open windows share current state. It contains no folder metadata and stops when the user chooses no model.

Rank & Folder uses a dedicated ephemeral connection that disables caches, cookies, and proxy configuration, rejects every redirect, and validates the final scheme, host, and port. It does not connect that API client to an internet hostname. Ollama can contact the internet when fulfilling a model-pull request. A model-page link can open the default browser when the user selects it.

The second path exists only after the user chooses **Set It Up for Me**. It downloads the exact `ollama-darwin.tgz` asset for pinned release 0.32.15 from GitHub over HTTPS. Redirects are accepted only to a small allowlist of GitHub release-asset hosts. Before extraction, Rank & Folder checks a bounded file size and the published SHA-256 `9ab0ac4747946620a2464054f3c44a55aa146e9fccb5c366ee18e43fd1930b90`. It lists and rejects absolute or parent-traversing archive members, constrains enumeration counts and symlink destinations, and verifies the extracted `ollama` executable with `codesign --verify --strict` after installation and before each launch. Because a valid signature shows only that a program is unchanged since it was signed, Rank & Folder also records that executable's code directory hash at install time, when it is known to have come from the checksum-verified archive, and requires the same hash before every later launch. A replacement placed in the support folder and signed again therefore fails, where signature verification alone would accept it. A runtime installed before this check existed has no recorded hash and adopts its current one on first launch; removing and reinstalling the runtime records a hash tied to a verified archive.

The managed runtime and its model directory live below `~/Library/Application Support/Rank & Folder/Ollama`. Rank & Folder gives the child a fixed environment rather than a copy of its own, so no `OLLAMA_` variable present when the app was launched can reach it. That environment binds the child to `127.0.0.1:11434`, restricts accepted origins to that same address, points `OLLAMA_MODELS` at the private model directory, disables Ollama cloud mode, and passes nothing else beyond `PATH`, `HOME`, and `TMPDIR`. Rank & Folder stops its child at app termination and offers removal controls. If something already answers on the fixed port, Rank & Folder treats it as an external Ollama service and does not start a second copy. This loopback service is not authenticated; output remains untrusted and validated.

Any local process can potentially listen on a loopback port. Rank & Folder therefore treats Ollama output as untrusted and validates it before display or use. This prevents a forged response from becoming arbitrary code, but it does not authenticate the local Ollama service. Users should install Ollama and models from sources they trust.

There are no OpenAI, Anthropic, Gemini, or other remote inference requests, API-key fields, cloud credential items, or cloud-model controls in the current interface. Unsupported method preferences normalize to the current Ollama or no-model choices. Cloud support must not be added without provider-specific payload previews, suitable credential storage and removal controls, retention and cost disclosures, opt-in consent, request-domain restrictions, and security tests.

## Mac compatibility consent

The optional compatibility check reads coarse processor architecture, physical memory, macOS version, and available storage through local system APIs. It saves only the consent setting, not the raw snapshot. The snapshot remains in memory while Models needs it and is discarded when no longer retained by the view. The user can turn off and forget consent there.

This is an in-app consent mechanism, not a macOS TCC permission. Model-fit labels are conservative estimates and must not be presented as security or performance promises.

## Local data

The app’s local preferences contain selected folder paths and names, opaque filesystem identities and non-security-scoped identity bookmarks when available, schema v4 recipes and descendant scope, explicit branch boundaries, active state, appearance and text-size choices, onboarding completion, model/no-model choice, compatibility-consent choice, Ollama setup preference, and selected Ollama model identifier. Legacy v1-v3 profiles decode as exact-folder records with no bookmark. Raw folder summaries, prompts, responses, Mac specifications, and file contents are not persisted.

The guarded reset path clears the two saved-choice repositories and pending Finder request queue, restores app preferences, and reopens onboarding. By default it retains Ollama data. A separate opt-in can delete only the managed runtime and model directories below Rank & Folder’s own Application Support area. It does not enumerate or mutate selected folders, process queued Finder work, remove a separate external Ollama installation or library, change Finder’s current views, or attempt to alter macOS permission records.

See [PRIVACY.md](PRIVACY.md) for the user-facing data explanation.

## Build and distribution trust

An ad-hoc-signed development ZIP does not identify an Apple-verified publisher or by itself demonstrate notarization. Code-signature verification can show that a bundle is internally consistent with its attached ad-hoc signature, but another party can modify and sign the bundle again. macOS may also treat each replacement build as a different program for Accessibility approval.

A public release should use Developer ID signing, Hardened Runtime, notarization, stapling, published SHA-256 checksums, and a clean CI build. Inspecting source and building locally can provide additional evidence, but it does not prove the absence of defects or a compromised toolchain. The standalone build script uses the installed Xcode toolchain and `librsvg` to render the included SVG icon; building does not download dependencies, Ollama, or models. Runtime/model downloads occur only later through explicit Model Center actions.

Developer ID identifies a signer, notarization records Apple’s automated acceptance of a submitted artifact, and a published checksum permits byte-for-byte comparison with that release. None alone proves source equivalence, privacy behavior, or the absence of vulnerabilities.

The current direct-distribution configuration leaves the main app unsandboxed for its optional Accessibility-driven Finder control. Source behavior is narrower than that process capability, but macOS does not enforce Rank & Folder’s saved-folder boundary on the main process. A malicious or compromised replacement could access other user-readable files; signing identity, notarization status, checksum verification, and source review therefore matter. The optional Finder Sync target is configured as sandboxed and uses a matching App Group in signed source builds; the contents and entitlements of each distributed artifact must still be inspected. A possible future hardening path is to separate networking and Finder control into least-privilege processes.

## Reporting a vulnerability

Do not publish an exploitable vulnerability before a fix is available. After the repository is public, use a private GitHub security advisory. Include the affected version, reproduction steps, impact, and relevant logs, with personal folder paths and file names removed.
