# Zigboard UI

Minimal keyboard-first HTML/JS UI shell for the clipboard manager.

## Usage

Open `index.html` in a browser while the IPC server is running on `http://127.0.0.1:8080`.

## Keyboard Shortcuts

- **↑/↓** - Navigate history items
- **Enter** - Copy selected item to clipboard
- **Ctrl+P** - Pin/unpin selected item
- **Del** - Delete selected item
- **Ctrl+F** - Focus search bar
- **Esc** - Close window

## Architecture

Pure presentation layer with zero business logic:
- Fetches JSON from IPC endpoints
- Renders items with keyboard navigation
- Delegates all operations to backend via HTTP

Lines of code: 147 (HTML + JS combined)
