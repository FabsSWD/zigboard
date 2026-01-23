# Zigboard - Clipboard Manager

✅ **Successfully compiled with Zig 0.15.2!**

## Quick Start

### 1. Run the Daemon

```bash
# Build and run
zig build run

# Or run the binary directly
./zig-out/bin/zigboard
```

You should see:
```
Zigboard daemon started on http://127.0.0.1:8080
Open ui/index.html in your browser
```

### 2. Open the UI

While the daemon is running, open `ui/index.html` in your web browser. The UI will automatically connect to the IPC server at `http://127.0.0.1:8080`.

### 3. Test the API

In a new terminal (while daemon runs):

```bash
# Get clipboard history (empty on first run)
curl http://127.0.0.1:8080/history

# Expected response:
# {"items": []}
```

## Keyboard Shortcuts (in UI)

- **↑/↓** - Navigate clipboard history
- **Enter** - Copy selected item to system clipboard
- **Ctrl+P** - Pin/unpin selected item
- **Del** - Delete selected item
- **Ctrl+F** - Focus search bar
- **Esc** - Close window

## Architecture

Clean Architecture implementation:
- **Domain** - Core business rules (ClipboardItem, Session, ClipboardHistory)
- **Application** - Use cases (Add, List, Pin, Delete, InitializeSession)
- **Adapters** - Linux clipboard, file persistence, HTTP IPC
- **Infrastructure** - Daemon lifecycle with signal handling
- **UI** - Keyboard-first HTML/JS interface (147 LOC)

## Development

```bash
# Run tests
zig build test

# Generate documentation
zig build docs

# Build only
zig build
```

## Stopping the Daemon

Press `Ctrl+C` or send SIGINT/SIGTERM signal.

## Known Limitations

- File persistence (JSON save/load) is currently stubbed due to Zig 0.15.2 API changes
- Clipboard monitoring is not yet wired to the daemon tick loop
- Filter function returns all items when search is active (proper filtering needs allocator)

## Project Structure

```
├── src/
│   ├── domain/          # Business entities
│   ├── application/     # Use cases
│   ├── adapters/        # External interfaces
│   ├── ipc/            # HTTP server & handlers
│   ├── infrastructure/ # Daemon lifecycle
│   ├── lib.zig         # Public API
│   └── main.zig        # Entry point
├── ui/
│   ├── index.html      # UI shell
│   └── app.js          # Client logic
└── build.zig           # Build configuration
```

## Next Steps

To complete the implementation:
1. Wire clipboard listener to daemon tick
2. Implement JSON persistence with new Zig API
3. Add proper filtering with allocator
4. Implement global keyboard shortcut
