# Repo2Prompt

A macOS app that turns a repository into a structured prompt for UI-gated models. Wanted something native without paying $15 per month. 

<img width="994" height="632" alt="image" src="https://github.com/user-attachments/assets/030acd2f-412f-4c94-9904-8c08b48a47d3" />

## Features

- File tree with checkboxes to pick what to include
- Include/exclude glob filters (e.g. `*.swift`, `.build, DerivedData`)
- Token count estimates per file and total
- Optional line numbers, git diff, and custom instructions
- Starred and recent folders in the sidebar

## Install

Download `Repo2Prompt.zip` from the [latest release](../../releases/latest), unzip, and drag to Applications.

On first launch, macOS will block the app because it's not notarized. To open it, go to the `Privacy & Security` settings screen and elect to open it.

Requires macOS 26 or later.
