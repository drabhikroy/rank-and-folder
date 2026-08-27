# Apple API constraints

This document records the platform boundaries that shape Rank & Folder. Apple documentation and SDK behavior should be checked again before each release.

## Finder view settings

Apple's [Finder sorting guide](https://support.apple.com/guide/mac-help/sort-and-arrange-items-in-the-finder-on-mac-mchlp1745/mac) documents one Sort By choice and one Group By choice. It does not document an API for an arbitrary ordered list of grouping and sorting descriptors.

Rank & Folder therefore keeps one general Sections and Item Order recipe, but applies it to Finder only when every saved rule can be represented. Recipes with additional levels remain available in Rank & Folder's read-only preview.

## Finder Sync

Apple's [Finder Sync framework](https://developer.apple.com/documentation/findersync) provides monitored directories, observation callbacks, badges, contextual menus, and a toolbar item. It does not expose Finder's Group By or Sort By settings.

Rank & Folder uses the optional extension only as a command surface. The extension forwards the Finder target to the containing app. The app performs profile resolution, identity checks, boundary checks, and Finder control.

## Finder scripting

Finder's scripting dictionary exposes parts of list and icon view configuration but does not provide a complete, view-independent Group By plus Sort By interface. Apple events therefore cannot reproduce every Finder-compatible Rank & Folder recipe. Rank & Folder does not request Automation permission or send Finder Apple events.

## Accessibility

The public Accessibility API can inspect and invoke another app's accessible controls, but it is UI automation rather than a semantic Finder settings API. The user must approve the exact app under **Privacy & Security > Accessibility**.

Rank & Folder reads Finder's `kAXDocumentAttribute`, `kAXURLAttribute`, and standard document proxy as candidate folder locations. It verifies the candidate against the resolved target before acting. It discovers labeled Group and Sort controls instead of relying on fixed child positions. If Finder is inactive, the location is unavailable, or a control cannot be verified, no change is made.

The user-initiated **Open in Finder and Apply** path can use an exact title match for a short period only when Finder omits supported location attributes. Passive matching and descendant authorization never rely on a title.

Accessibility approval is tied to code identity. Ad-hoc replacement builds may need approval again. Developer ID signing gives public releases a stable signer identity, but the exact artifact still needs testing.

## Folder metadata and identity

Rank & Folder uses public `FileManager`, `URLResourceValues`, Uniform Type Identifiers, `NSWorkspace`, and File Provider APIs. It lists one folder's immediate visible children and reads standard metadata. These APIs do not provide Finder view settings and are not used to read file contents.

Foundation bookmarks are created with `withoutImplicitSecurityScope` and resolved without implicit access. They provide identity evidence, not hidden access. Descendant authorization uses `FileManager.getRelationship`, resolved symlinks, live volume identity, and compatible File Provider classification. An unknown relationship fails closed.

## Distribution

Mac App Store distribution requires App Sandbox, while Rank & Folder's Accessibility-based Finder control is designed for Developer ID distribution outside the store. The containing app is not sandboxed. The optional Finder Sync extension is sandboxed and uses the configured App Group.

Hardened Runtime is enabled in the project, but that setting alone does not establish Developer ID signing or notarization. Follow Apple's [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for the exact release artifact.

## Mechanisms not used

- `.DS_Store` reading or writing
- Private Finder frameworks
- Code injection, method swizzling, or process modification
- Accessibility automation inside Finder Sync
- Lexical path prefixes as proof of ancestry
- Identity bookmarks as access grants
- Silent removal of recipe levels to fit Finder
- Cloud model requests or credential storage

## Optional Ollama boundary

Ollama is not an Apple framework. Rank & Folder's client is fixed to `127.0.0.1:11434`. The optional managed path downloads a pinned official archive, checks its checksum and archive structure, verifies the executable's macOS signature, and stores it under Rank & Folder's Application Support directory. Ollama controls its own external model downloads and behavior.
