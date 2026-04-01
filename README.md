# Repo2Prompt

A macOS app that turns a repository into a structured prompt you can paste into an LLM.

Pick a folder, select the files you want, and hit **Copy Prompt**. The output includes a directory tree, file contents, and optionally a git diff - all wrapped in XML tags ready for Claude, ChatGPT, etc.

## Features

- File tree with checkboxes to pick what to include
- Include/exclude glob filters (e.g. `*.swift`, `.build, DerivedData`)
- Token count estimates per file and total
- Optional line numbers, git diff, and custom instructions
- Starred and recent folders in the sidebar

## Install

Download `Repo2Prompt.zip` from the [latest release](../../releases/latest), unzip, and drag to Applications.

Requires macOS 26 or later.
