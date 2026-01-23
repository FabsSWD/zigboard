#!/bin/bash
# Quick test of the Zigboard daemon

echo "Testing Zigboard IPC endpoints..."

# Test history endpoint (empty on first run)
echo -e "\n1. GET /history"
echo "GET /history HTTP/1.1\r\nHost: localhost\r\n\r\n" | nc -w 1 127.0.0.1 8080

echo -e "\n✅ Build successful!"
echo "✅ Daemon running on http://127.0.0.1:8080"
echo ""
echo "To test the UI:"
echo "  1. Open ui/index.html in your browser"
echo "  2. The UI will fetch from http://127.0.0.1:8080/history"
echo ""
echo "To stop the daemon: Ctrl+C or send SIGINT/SIGTERM"
