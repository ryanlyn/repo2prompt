# Repo2Prompt

A macOS app that turns a repository into a structured prompt for UI-gated models. Wanted something native without paying $15 per month. 

<img width="1112" height="812" alt="image" src="https://github.com/user-attachments/assets/096cfb36-ef35-4d2f-b615-60862679d44c" />

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
