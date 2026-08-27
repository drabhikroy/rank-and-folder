# Contributing

Thanks for helping improve Rank & Folder.

## Before opening a pull request

1. Keep Finder-specific accessibility knowledge inside `FinderAccessibilityClient`.
2. Keep one canonical Sections + Item Order recipe. Do not reintroduce a user-facing Finder/advanced mode switch or silently drop levels to fit Finder.
3. Do not add `.DS_Store` mutation, private frameworks, code injection, method swizzling, undocumented Finder preference writes, or UI automation inside the Finder extension.
4. Add or update core tests for schema migration, recipe invariants, Finder representation, resolver, queue, and persistence changes.
5. Run `swift test` and an unsigned complete Xcode build.
6. Test signed Finder behavior manually when a change touches the Accessibility adapter or optional extension.
7. Update privacy, security, Help, and distribution text whenever a capability or data path changes.

## User-facing language

Use Rank & Folder’s public terms consistently:

- **Sections** create visible headings;
- **Item Order** decides what appears first and breaks ties;
- **Folder preview** displays a complete recipe that Finder cannot reproduce.
- **Use this layout in subfolders** shares one saved choice with verified folders below it;
- **Leave this folder and its subfolders alone** creates a branch exception.

Finder’s **Group By** and **Sort By** terms, and the technical term “inheritance,” belong in Help, compatibility explanations, and developer documentation. Prefer ordinary Mac language such as “closest saved choice,” “includes subfolders,” and “leave this branch alone” in the main workflow. A nontechnical reader should understand an action without knowing Finder APIs, extensions, schemas, model runtimes, or Terminal.

Avoid claims such as “best layout,” “100% safe,” “no networking,” or “works on every Mac.” Describe the exact behavior and limitation.

## Interface changes

Keep the app recognizably macOS-native and preserve a clear reading order. Reuse shared surfaces, setup rows, status banners, and recipe controls before introducing a new pattern. Each screen should have one visually dominant next action.

Every color-coded state needs a word and symbol equivalent. Every icon-only button needs an accessibility label and Help text. Respect Reduce Motion, system appearance, increased contrast, keyboard navigation, and the selected color-assistance mode.

For interface pull requests, test at minimum:

- an empty and populated saved-folder list;
- first-run tour completion, skip, every suggestion branch, and reopening from Help;
- Help search with results and no results, including Appearance & Color Vision;
- zero, one, and several Section levels, plus several Item Order tie-breakers;
- automatic Finder and Folder preview presentation choices;
- exact-folder overrides, closest verified subfolder choice, a leave-alone boundary, a paused branch, a legacy/path-only profile, malformed boundary storage, and duplicate or unavailable records;
- confirm a path-only profile may retain exact Finder automation but cannot open Folder preview or build a model summary until it is removed and added again;
- exercise concurrent add attempts from two windows and confirm the final post-await duplicate check leaves only one exact profile or boundary;
- inherited Finder-compatible and rich recipes; verify that Finder and Folder preview both operate on the target child while naming the saved source accurately;
- optional Finder automation off, granted, stale from an earlier build, and unavailable for a File Provider folder; an identity-verified profile’s preview must remain usable without it;
- Ollama connected, unavailable, downloading, failed, and several-model states;
- compatibility consent off, on, and forgotten;
- minimum and large window sizes, long names/paths, Light, Dark, all color-assistance modes, VoiceOver, Full Keyboard Access, Increased Contrast, and Reduce Motion;
- sidebar **+** and **−**, Delete key, contextual removal, confirmation cancellation, and confirmation acceptance.

Include before/after screenshots for layout changes and note any intentional departure from [Docs/Interface-Design.md](Docs/Interface-Design.md).

## Local models

Model output is untrusted data. Any suggestion provider must:

- receive the smallest disclosed payload needed for the task;
- exclude file contents, filenames, paths, tag text, and individual records unless a future design obtains separate informed consent;
- restrict outputs to supported recipe criteria and directions;
- enforce response-size, count, and timeout limits;
- show the provider, payload summary, rationale, and complete recipe before saving;
- report provider failure without silently switching to another method;
- never apply a model result automatically or give a model Finder, filesystem-write, shell, or tool access.

The current Ollama client must remain fixed to loopback unless a separately reviewed feature intentionally changes that boundary. New catalog entries need a stable model identifier, current size estimate, conservative memory estimate, license label, and official model page. Do not imply that a compatibility badge promises performance.

The Rank & Folder-managed Ollama option is also security-sensitive. A runtime update must pin an exact official HTTPS release URL and SHA-256 value; keep redirect hosts narrowly allowlisted; reject unsafe archive paths and escaping symlinks; verify the extracted program before execution; and keep executable paths and arguments independent of model or user text. Test cancellation, a bad checksum, a rejected redirect, an unsafe archive, removal failure, and an already-running external service. Document which third-party release was reviewed and verify the exact archive outside the app before publishing.

Do not activate a cloud provider without all of the following in the same reviewed change:

- an exact pre-request payload preview;
- provider-specific privacy, retention, and cost disclosure;
- explicit opt-in consent;
- Keychain credential storage with removal controls;
- fixed allowlisted domains and transport security;
- request/response bounds, cancellation, and error handling;
- tests proving that other modes never use the cloud;
- updated `PRIVACY.md`, `SECURITY.md`, security review, Help, onboarding, and release notes.

## Security-sensitive changes

Treat Accessibility, networking, model downloads, credentials, persistence, folder identity, relationship resolution, boundaries, and folder enumeration as security-sensitive. In the pull request, list:

- what data is read, saved, or transmitted;
- exact destinations and which component performs any external download;
- permission or in-app consent changes;
- failure behavior and revocation path;
- tests and manual checks performed.

Inheritance changes must preserve these core rules:

- an on verified exact choice wins;
- only a verified closest saved choice with descendant scope can be inherited;
- paused, boundary, broken, replaced, cross-volume, provider-unknown, and ambiguous branch records fail closed as specified by the resolver;
- migrated or path-only records never gain descendant authority silently;
- a path-only legacy record never authorizes metadata enumeration even when its exact Finder automation remains available;
- profile and boundary storage loads as one unit, so malformed boundary data disables all profiles instead of failing open;
- any add flow that awaits relationship checks repeats exact-profile and exact-boundary duplicate checks immediately before mutation;
- lexical path prefixes never authorize a relationship;
- the target URL and identity remain separate from the source profile through monitoring, queues, Finder verification, status, and Folder preview;
- turning on subfolder use never becomes a recursive metadata scan;
- identity bookmarks remain non-security-scoped unless a separately reviewed architecture intentionally changes the access model.

Automation bug reports should include macOS version, Finder language, active Finder view, Xcode version, expected recipe, and Rank & Folder’s status message. Model reports should add provider, model identifier, availability state, and whether fallback was used. Redact folder paths, filenames, prompts, and personal metadata.

By contributing, you agree that your contribution is licensed under the repository’s PolyForm Noncommercial License 1.0.0.
