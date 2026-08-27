# Privacy

Rank & Folder 1.0.0 is local-first. The reviewed source contains no analytics, advertising, telemetry, account system, or automatic cloud synchronization.

## Information saved on this Mac

Rank & Folder saves these settings in local macOS preferences:

- each selected folder’s path, display name, opaque filesystem resource identity when available, non-security-scoped identity bookmark when available, Sections, Item Order, exact/subfolder scope, and active state;
- explicit **leave this branch alone** boundaries, including their path, display name, identity bookmark, resource identity, and timestamps;
- appearance, text-size, and color-assistance choices;
- whether the welcome tour is complete;
- the selected model/no-model choice and Ollama model identifier;
- whether you allowed the optional Mac compatibility check.

The raw Mac specifications, folder-summary snapshots, model prompts, model responses, and model explanations are not saved. If you accept a proposed layout, only the resulting organization recipe is saved. Removing Rank & Folder does not automatically remove its macOS preferences.

An extension-on developer build can keep the same profile data in its configured App Group so the app and optional Finder extension can share it. The standalone release uses the app’s ordinary preferences.

## Resetting Rank & Folder

**Settings > Reset > Reset Rank & Folder** removes Rank & Folder’s saved layouts, leave-alone boundaries, appearance and model choices, onboarding completion, compatibility consent, selected Ollama model identifier, and pending Finder requests, then starts the Quick Tour. A confirmation lists this scope before reset.

Reset does not delete, move, rename, or open files. It keeps Ollama and downloaded models unless the person turns on **Also remove Rank & Folder’s local-model downloads** in the reset panel. That option deletes only the runtime and model directories inside Rank & Folder’s own Application Support area; it does not remove a separate Ollama Desktop installation or that installation’s model library. Reset does not change Finder’s current view or revoke macOS Accessibility, Local Network, or Files & Folders permissions. Those system permissions remain under System Settings until the user changes them.

## Folder access

The reviewed Rank & Folder code reads folder names and standard metadata, not file contents. When you choose **Open** in Folder preview, macOS hands that item to its normal default app; macOS, Finder, Ollama, downloaded models, and opened apps have their own privacy behavior.

For newly added or explicitly refreshed folders, Rank & Folder saves the operating system’s opaque resource identity and a regular identity bookmark created with `withoutImplicitSecurityScope`. This bookmark does not grant implicit folder access. Rank & Folder resolves it without showing UI or mounting a volume, and it does not call `startAccessingSecurityScopedResource` for this identity check.

Before Folder preview or a model request reads metadata, Rank & Folder checks the live target identity so a folder deleted and replaced at the same path is not silently treated as the original. A path-only schema record may retain exact Finder automation, but Rank & Folder will not enumerate that folder for preview or a model request. Remove the saved layout and add the folder again before using either metadata feature. Such records receive no descendant authority silently.

For Finder-compatible recipes, it reads the focused Finder window’s folder URL through Accessibility. If Finder and a cloud provider describe the same folder using different paths, Rank & Folder can compare their read-only filesystem resource identifiers.

Folder preview lists only the selected folder’s immediate visible children. It reads the names and standard metadata needed to display and organize them: item type, extension, creation and modification dates, size, and Finder tags. It does not recursively scan subfolders, inspect hidden items, or modify files. Rank & Folder does not directly read, parse, or write `.DS_Store`; Finder may persist its own native view preferences after Rank & Folder operates Finder controls.

Turning on **Use this layout in subfolders** does not enumerate or recursively scan those subfolders. When a person opens or explicitly previews one target folder, Rank & Folder compares that target with saved choices and boundaries. The closest verified saved choice is used unless the target has its own saved layout or a branch boundary stops the search. A paused saved choice blocks automatic and inherited use on that branch. If verification is unavailable or ambiguous, Rank & Folder leaves the target alone.

Profiles and leave-alone boundaries are loaded together. If the stored boundary data is malformed or cannot be decoded, Rank & Folder disables the loaded profiles rather than risk applying one across a boundary it could not read.

For descendant verification, the current source uses a non-security-scoped bookmark, a live directory relationship, live volume identity, and File Provider classification. Both folders must be ordinary local locations or belong to the same positively identified File Provider domain. An unknown provider result blocks descendant use. The target folder remains separate from the source profile: metadata and Folder preview come from the target child, while only the saved recipe comes from its source.

## Optional local models

Models are optional, and model output never applies itself. If you choose no model, Rank & Folder does not create a model or rules-based layout for you. Before asking the selected local model, Rank & Folder builds an aggregate summary from the selected folder’s immediate visible items. The summary can contain:

- total visible items and folder count;
- counts of broad file categories;
- counts of the ten most common extensions;
- the number of tagged items, but not tag text;
- counts of items modified recently and the overall modification-date span;
- combined file size.

The summary contains no filenames, paths, file contents, or individual file records.

If you choose Ollama, Rank & Folder sends the same aggregate summary to Ollama at `http://127.0.0.1:11434` on this Mac. The current app does not send an Ollama prompt to a remote hostname.

While the local-model path is selected, Rank & Folder checks that loopback endpoint every two seconds for the Ollama version and installed-model names so all open windows stay current. These checks contain no folder path, filename, metadata summary, or file content. Choosing no model stops them.

Model Center can ask the local Ollama service to download a selected model and show progress. Ollama contacts its model source, so Ollama’s privacy, security, and network behavior applies. Model-page links open in the default browser only when selected.

Model Center can also ask Ollama to delete one recognized installed model after confirmation. For Rank & Folder’s managed runner, that model is in Rank & Folder’s private support directory. If Rank & Folder is connected to an existing Ollama service, its model library can be shared with other apps; the confirmation warns that deleting the model can therefore remove it for those apps too.

If you choose **Set it up for me**, Rank & Folder itself downloads the exact Ollama 0.32.15 macOS archive from the official `github.com/ollama/ollama` release. HTTPS redirects are limited to GitHub release-asset hosts. Rank & Folder checks the archive against the SHA-256 published on that release, rejects unexpected archive paths, checks the extracted executable’s macOS code signature, and only then runs it on localhost. The runtime and managed model weights are stored under `~/Library/Application Support/Rank & Folder/Ollama`, not in `/Applications`, `/usr/local/bin`, or `~/.ollama`. They remain until you remove them in Model Center or remove that support folder.

The managed Ollama executable is third-party software and runs as a child process of Rank & Folder. It receives only the same aggregate prompt described above. If an existing Ollama service is already running, Rank & Folder uses it instead of starting its managed copy; that installation controls its own storage. Ollama documents its local API at [docs.ollama.com/api/introduction](https://docs.ollama.com/api/introduction).

There is no cloud model choice, cloud request implementation, API-key entry, or cloud credential storage in the current interface. Unsupported saved model-method values are normalized to the local-model or no-model choices.

## Optional Mac compatibility check

Model Center can estimate which local models may fit this Mac. It asks through an in-app choice before reading coarse processor architecture, physical memory, active processor count, macOS version, and available storage. This is Rank & Folder’s own consent control; macOS does not provide a separate privacy permission for these system facts.

The check runs locally. Raw specifications are held only in memory while needed and are not saved or shared. Only the allow/deny choice is saved. Turn it off and forget that choice from the compatibility panel in **Models**.

Compatibility labels are approximate. They are not uploaded, and they do not promise model speed or quality.

## Accessibility permission

Accessibility is optional and needed only when Rank & Folder identifies the focused Finder folder and operates Finder’s existing view controls for a recipe Finder can reproduce. Editing layouts, choosing subfolder scope, adding or removing leave-alone boundaries, Models, model requests, and Folder preview do not require Accessibility. Metadata views still require the saved-folder identity described above, so a path-only profile must be removed and added again first.

macOS grants Accessibility as a broad permission. Rank & Folder deliberately limits its use to Finder location verification and Finder’s view controls. Revoke it at any time under **System Settings > Privacy & Security > Accessibility**; Finder automation then stops.

## Other permissions

macOS may separately ask for access when you add a folder under Downloads, Documents, Desktop, a File Provider, a network volume, or a removable volume. Rank & Folder uses available access for a folder you explicitly add, or a verified descendant when subfolder use is on, and reads only that target’s immediate visible names and standard metadata. Revoke these categories under **System Settings > Privacy & Security > Files & Folders**.

The current source does not declare a need for Full Disk Access, Screen Recording, Input Monitoring, Automation, camera, microphone, contacts, calendar, or location access. The optional Finder extension is not required. A built artifact and its entitlements still need verification before each release.

For implementation-level details, read [SECURITY.md](SECURITY.md) and [Docs/Security-Review.md](Docs/Security-Review.md).
