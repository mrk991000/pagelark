# Pagelark

A free, open-source freeform notebook for Windows, macOS and Linux.
Click anywhere on a page and start typing and drawing, like on paper.

## Features

- **Freeform pages**: double-click anywhere to place a text box, then drag, resize and colour it
- **Images**: add a picture from a file, or paste one from the clipboard (Ctrl/Cmd + V), then move and resize it
- **Pen and eraser**: draw ink right on the page, in five colours
- **Notebook structure**: sections and pages
- **Safe by default**: a backup copy is kept every day, and your light/dark choice is remembered
- **Search across all pages**: `Ctrl/Cmd + F`
- **Big scrolling canvas** for each page
- **Light and dark mode**
- **Export**: copy a page as Markdown (text only), or copy a full notebook backup, images included, and restore it later
- **Shortcuts**: `Ctrl/Cmd + N` adds a page
- **Local first**: notes are saved to `Documents/Pagelark/notebook.json` and pictures to `Documents/Pagelark/images/`

## Download

Windows, macOS, Linux and Android. Get the latest version for your system from the
[Releases page](https://github.com/mrk991000/pagelark/releases/latest).

The apps are not code-signed yet, so your system may show a warning the first time:

- **Windows:** click "More info", then "Run anyway"
- **macOS:** right-click the app, choose "Open", then confirm
- **Linux:** extract the archive and run the `notebook_app` file
- **Android:** open the `.apk`, and allow installs from your browser or file manager when Android asks

## Build from source

You need the [Flutter SDK](https://flutter.dev).

```
flutter pub get
flutter run -d windows   # or macos / linux / a connected Android phone
```
