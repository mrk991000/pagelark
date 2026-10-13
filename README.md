# Pagelark

A free, open-source freeform notebook for Windows, macOS and Linux.
Click anywhere on a page and start typing, like paper. No account, no cloud,
and your notes are plain JSON files that you own.

## Features

- **Freeform pages**: double-click anywhere to place a text box, then drag, resize and colour it
- **Notebook structure**: sections and pages
- **Search across all pages**: `Ctrl/Cmd + F`
- **Big scrolling canvas** for each page
- **Light and dark mode**
- **Export**: copy a page as Markdown, or copy a full notebook backup and restore it later
- **Shortcuts**: `Ctrl/Cmd + N` adds a page
- **Local only**: saved to `Documents/Pagelark/notebook.json`

## Download

Get the latest version for your system from the
[Releases page](https://github.com/mrk991000/pagelark/releases/latest).

The apps are not code-signed yet, so your system may show a warning the first time:

- **Windows:** click "More info", then "Run anyway"
- **macOS:** right-click the app, choose "Open", then confirm
- **Linux:** extract the archive and run the `notebook_app` file

## Build from source

You need the [Flutter SDK](https://flutter.dev).

```
flutter pub get
flutter run -d windows   # or macos / linux
```

## Roadmap

- Images pasted onto the page
- Ink / pen drawing
- Optional sync between devices
- Android version

## License

MIT
