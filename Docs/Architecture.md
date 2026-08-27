# Architecture

Rank & Folder keeps recipe storage, folder identity, Finder control, preview rendering, and optional model work in separate components. The boundaries are intentional: a failure in one area should not grant another area more authority.

## Data model

`RankFolderProfile` stores a folder identity, an `OrganizationRecipe`, exact-folder or descendant scope, active state, timestamps, and schema version. `OrganizationRecipe` contains ordered Section rules and Item Order rules.

`FolderInheritanceBoundary` records a branch that Rank & Folder must leave alone. Profiles and boundaries are loaded as one configuration so corrupt boundary data cannot leave profiles active without their exceptions.

Current profiles contain a regular Foundation bookmark created with `withoutImplicitSecurityScope` and a filesystem resource identifier when available. The bookmark is identity evidence, not an access grant.

## Storage

`UserDefaultsProfileRepository` encodes profiles and boundaries as JSON in `UserDefaults`. Source builds with the Finder extension use the configured App Group. The standalone app uses ordinary application preferences.

`ProfileStore` owns user-facing mutations. It repeats duplicate checks immediately before writes when an earlier filesystem check suspended the operation. Removal changes only saved Rank & Folder state.

## Folder resolution

`SecureProfileResolver` selects the recipe for a target folder:

1. An active, verified exact profile wins.
2. Otherwise the closest verified active ancestor with descendant scope wins.
3. A boundary, paused profile, unavailable identity, ambiguous record, cross-volume relationship, or unknown File Provider relationship blocks the branch as defined by the resolver.
4. A lexical path prefix never authorizes inheritance.

`ProductionFolderRelationshipChecker` resolves symlinks, requires live directory relationships, compares volume identity, and permits File Provider descendants only when both locations are known local or belong to the same provider domain.

The resolved result keeps the source profile and target folder separate. The source supplies the recipe. The target is the folder Finder verifies and the preview reads.

## Presentation selection

`RecipePresentationResolver` decides how a complete recipe can be shown:

- A Finder-compatible recipe maps to one supported Section and one supported Item Order rule.
- Any additional level, unsupported criterion, or explicit direction that Finder automation cannot preserve uses Rank & Folder preview.

No conversion silently discards a saved choice.

## Finder automation

`FinderAccessibilityClient` is the only component that knows Finder's accessible interface. It verifies active Finder and the focused folder, then operates labeled Finder controls through the public Accessibility API. Searches are bounded and failures stop the operation.

`FinderFolderMonitor` observes Finder activation and window changes. `AutomationCoordinator` resolves a current target immediately before an apply and rejects stale requests. Accessibility is optional.

The Finder Sync extension is a small command surface. It registers eligible roots and queues the target reported by Finder. The containing app performs identity, boundary, relationship, and recipe checks. The extension does not automate Finder or enumerate folder contents.

## Folder preview

`AdvancedFolderLoader` reads the immediate visible children of an identity-verified target with public Foundation metadata APIs. It does not recurse or read file contents.

`AdvancedHierarchyBuilder` applies the saved Section and Item Order rules in memory. `FinderColumnPreview` renders all loaded items with real macOS file icons in a read-only, scrollable view. Open actions are delegated to `NSWorkspace`.

## Optional local models

`ModelCenterViewModel.shared` is the app-wide Ollama inventory source. It combines the service's available and currently running model lists and keeps a valid explicit selection stable.

`FolderSnapshotBuilder` creates aggregate counts and ranges from one folder's immediate visible items. `OllamaClient` sends that summary to the fixed loopback endpoint. `SuggestionRecipeValidator` restricts the response to supported criteria, directions, counts, and text limits. A proposal is not saved until the user reviews its grouping preview and approves it.

`ManagedOllamaRuntime` can install a pinned Ollama build under Rank & Folder's Application Support directory. The installer limits redirect hosts, verifies download size and SHA-256, validates archive paths and symlinks, checks the executable signature, and rechecks that signature before launch. Cancellation prevents a staged install from becoming active after reset.

## App scenes and state

SwiftUI window scenes provide the main profile editor, Quick Tour, Help, Settings, Reset, Models, model comparison, model results, preview, and download review. Each content window has a minimum size and remains movable and resizable.

`AppearancePreferences` supplies color scheme, text scale, and color-vision settings at every scene root. `OnboardingStore` owns tour completion and local-model choice. Opening the tour always starts at the first page.

## Failure policy

Rank & Folder prefers a visible error or read-only fallback to a guessed action:

- identity uncertainty blocks metadata reads and descendant use;
- malformed configuration blocks profile loading;
- stale automation requests are discarded;
- a Finder control mismatch makes no view change;
- an unsupported recipe stays available in Rank & Folder preview;
- invalid model output is rejected;
- reset and removal never touch selected folders or their contents.

## Extension points

New custom grouping criteria belong in the recipe model, validator, hierarchy builder, and preview. They should not be added to Finder conversion unless Finder can reproduce them exactly. A future model provider needs its own explicit consent, payload disclosure, transport boundary, credential handling, validation, and tests.
