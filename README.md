# MadQuill — Native Markdown Quick Look for macOS

MadQuill is a macOS Quick Look Preview Extension project that renders Markdown files in Finder using only Apple-native APIs.

It is designed for developers who want a clean reference implementation of:

- modern Quick Look extension architecture (no legacy `.qlgenerator`),
- native Markdown parsing (`NSAttributedString(markdown:options:baseURL:)`),
- explicit error handling and guardrails suitable for production hardening.

---

## Features

- ✅ Finder Quick Look preview for Markdown content
- ✅ Native rendering pipeline (no third-party Markdown engine)
- ✅ Data-based Quick Look extension (`QLPreviewProvider`)
- ✅ File-size guardrail (prevents expensive previews on very large files)
- ✅ UTF-8 validation and explicit error previews
- ✅ Host app + embedded extension packaging pattern

---

## Architecture

The repository contains two targets:

1. **Host app** (`MadQuillApp`)  
   Required by macOS to ship/install app extensions.

2. **Quick Look preview extension** (`MarkdownQuickLookExtension`)  
   Handles preview generation for supported Markdown UTIs.

Core extension metadata is configured in:

- [MarkdownQuickLookExtension/Info.plist](./MarkdownQuickLookExtension/Info.plist)

Notable keys:

- `NSExtensionPointIdentifier = com.apple.quicklook.preview`
- `QLIsDataBasedPreview = true`
- `QLSupportedContentTypes` includes Markdown UTIs
- `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).PreviewProvider`

Rendering logic lives in:

- [MarkdownQuickLookExtension/Sources/PreviewProvider.swift](./MarkdownQuickLookExtension/Sources/PreviewProvider.swift)

Project generation is driven by:

- [project.yml](./project.yml) (XcodeGen spec)

---

## Requirements

- macOS 12.0+
- Xcode 15+ (tested here with Xcode 27 toolchain)
- Homebrew (recommended for installing XcodeGen)
- XcodeGen

---

## Quick Start (Developers)

### 1) Clone

```bash
git clone <your-fork-or-repo-url>
cd madquill
```

### 2) Install XcodeGen (if needed)

```bash
brew install xcodegen
```

### 3) Generate the Xcode project

```bash
xcodegen generate
```

This creates:

- `MadQuillQuickLook.xcodeproj`

### 4) Open in Xcode

```bash
open MadQuillQuickLook.xcodeproj
```

### 5) Configure signing

In Xcode:

1. Select target **MadQuillApp**.
2. Go to **Signing & Capabilities**.
3. Enable **Automatically manage signing**.
4. Select your development team.
5. Repeat for **MarkdownQuickLookExtension**.

> Tip: Replace placeholder bundle IDs (`com.example.madquill`) with your own reverse-DNS identifiers before distributing.

### 6) Build & run the host app

Run the **MadQuillQuickLook** scheme once.

This installs/registers the extension on your machine.

### 7) Refresh Quick Look services

```bash
qlmanage -r
qlmanage -r cache
```

Optionally restart Finder:

```bash
killall Finder
```

### 8) Test in Finder

1. Open Finder and select a `.md` file.
2. Press **Space** for Quick Look.
3. Verify rendered preview appears.

---

## Build from CLI

Generate project first:

```bash
xcodegen generate
```

Then build:

```bash
xcodebuild \
  -project MadQuillQuickLook.xcodeproj \
  -scheme MadQuillQuickLook \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

> `CODE_SIGNING_ALLOWED=NO` is useful for compile verification in CI or local validation.  
> To run/install extension locally, use normal signing in Xcode.

---

## How rendering works

`PreviewProvider` executes the following pipeline:

1. Read preview file data from `request.fileURL`
2. Enforce max size guardrail
3. Decode as UTF-8
4. Parse Markdown natively using:
   - `NSAttributedString(markdown:options:baseURL:)`
5. Convert attributed content to HTML payload
6. Return `QLPreviewReply(dataOfContentType: .html, ...)`

On failure, it returns a human-readable error preview (not a silent blank state).

---

## Supported content types

Current extension `Info.plist` declares:

- `net.daringfireball.markdown`
- `public.markdown`

If your Markdown files are tagged with additional UTIs in your environment, add them under `QLSupportedContentTypes`.

---

## Troubleshooting

## Extension not used by Finder

- Ensure host app has been run at least once after build.
- Re-run:
  ```bash
  qlmanage -r
  qlmanage -r cache
  ```
- Restart Finder:
  ```bash
  killall Finder
  ```
- Verify `QLSupportedContentTypes` values in extension `Info.plist`.

## Signing/build issues

- Confirm both targets use the same Team and valid development signing.
- Ensure bundle identifiers are unique and valid for your account.

## Preview shows fallback error panel

Common causes:

- file exceeds current size threshold,
- non-UTF-8 input,
- malformed content causing parse conversion errors.

Check extension logs in Console.app for diagnostics.

---

## Release and distribution

For a developer-facing GitHub release, the recommended delivery format is a **signed and notarized macOS DMG**.

### Recommended user flow

1. Download the DMG from GitHub Releases.
2. Open the DMG and drag the app into `/Applications`.
3. Launch the app once to register the Quick Look extension.
4. Refresh Quick Look caches if needed:

```bash
qlmanage -r
qlmanage -r cache
```

This is the least confusing experience for users who are not familiar with extension internals.

### Local packaging flow

```bash
chmod +x ./scripts/package_release.sh
APPLE_DEVELOPER_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/package_release.sh release
```

This script does the following:

- regenerates the Xcode project,
- archives the app in Release mode,
- signs the app bundle with your Developer ID certificate,
- creates a `.dmg` artifact,
- optionally submits the artifact to notarization if Apple credentials are present.

### GitHub Actions automation

The repository includes a starter workflow at:

- [.github/workflows/release.yml](./.github/workflows/release.yml)

It expects the following repository secrets:

- `MACOS_CERTIFICATE`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_DEVELOPER_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_PASSWORD`
- `APPLE_TEAM_ID`

This workflow:

- installs XcodeGen,
- imports the certificate into a temp keychain,
- builds the app,
- creates the distributable DMG,
- notarizes the release when credentials are configured,
- uploads the artifact and publishes it as a GitHub Release when a version tag is pushed.

### Notes on installer design

If you want a more “App Store style” installation experience, you can also package a `.pkg` installer later. In many internal tools, however, a DMG remains the easiest and most transparent option for developers who just want a working Quick Look extension.

### Quick Look registration check

After launching the app once, confirm the extension is registered properly:

```bash
qlmanage -r
qlmanage -r cache
```

Then test with a Markdown file in Finder by pressing **Space**. If the preview fails to appear, ensure the host app has been launched at least once and that the file extension matches one of the UTI entries in the extension `Info.plist`.

---

## Development notes

- This repo intentionally avoids third-party Markdown renderers.
- The extension currently favors robustness and predictable behavior over advanced Markdown features.
- For roadmap/history and phased design context, see:
  - [plan.md](./plan.md)

---

## Limitations (current implementation)

- Assumes UTF-8 input for preview generation.
- Large files above the guardrail return an explanatory message.
- No custom thumbnail extension yet (preview only).
- No advanced Markdown extras (Mermaid/KaTeX/highlight plugins).

---

## Contributing

Contributions are welcome, especially around:

- improved native styling fidelity,
- better handling of very large Markdown documents,
- broader Markdown UTI compatibility testing,
- automated validation workflows.

Please keep contributions aligned with the core rule: **native Apple APIs only for Markdown rendering**.

---

## License

Add your preferred license file (for example MIT) before public release.

