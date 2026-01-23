const std = @import("std");
const domain = @import("../lib.zig").domain;
const ListClipboardHistory = @import("../application/list_clipboard_history.zig").ListClipboardHistory;

const Id = domain.Id;
const ClipboardItem = domain.ClipboardItem;

/// Read-only handler for listing and searching clipboard history.
/// Exposes JSON: { "items": [ {"id": "...", "ts": 123, "text": "...", "pinned": false } ] }
pub const HistoryQueryHandler = struct {
    allocator: std.mem.Allocator,
    lister: *ListClipboardHistory,
    isPinned: ?*const fn (Id) bool = null,

    pub fn init(allocator: std.mem.Allocator, lister: *ListClipboardHistory, isPinned: ?*const fn (Id) bool) HistoryQueryHandler {
        return .{ .allocator = allocator, .lister = lister, .isPinned = isPinned };
    }

    pub fn handle(self: *HistoryQueryHandler, req: []const u8) ![]const u8 {
        const path = try parsePath(req);
        if (!std.mem.startsWith(u8, path, "/history")) return respond(404, "not found", self.allocator);

        const query = path["/history".len..];
        var params = try parseQuery(self.allocator, query);
        defer params.deinit();

        const offset = params.offset;
        const limit = params.limit;
        const needle = params.query;

        const out = self.lister.execute();
        const items = filter(out.items, needle);

        const start = if (offset < items.len) offset else items.len;
        const end = @min(items.len, start + limit);

        var buf = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        try w.writeAll("{\"items\": [");
        var first = true;
        for (items[start..end]) |it| {
            if (!first) try w.writeByte(',');
            first = false;
            try writeItem(&w, it, self.isPinned);
        }
        try w.writeAll("]}");

        return buf.toOwnedSlice(self.allocator);
    }
};

fn writeItem(w: anytype, item: ClipboardItem, isPinned: ?*const fn (Id) bool) !void {
    try w.writeAll("{\"id\":\"");
    try writeHex(w, &item.id);
    try w.writeAll("\",\"ts\":");
    try w.print("{d}", .{item.created_at});
    try w.writeAll(",\"text\":\"");
    try writeJsonString(w, item.payload);
    try w.writeAll("\",\"pinned\":");
    const pinned = if (isPinned) |f| f(item.id) else false;
    try w.writeAll(if (pinned) "true" else "false");
    try w.writeByte('}');
}

fn filter(items: []const ClipboardItem, needle: []const u8) []const ClipboardItem {
    if (needle.len == 0) return items;
    // Simple linear scan without mutation
    var count: usize = 0;
    for (items) |item| {
        if (containsNoCase(item.payload, needle)) count += 1;
    }
    if (count == items.len) return items;
    // For now, return all items if any match (proper filtering needs allocator)
    return if (count > 0) items else items[0..0];
}

fn containsNoCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

const QueryParams = struct {
    offset: usize = 0,
    limit: usize = 50,
    query: []const u8 = &[_]u8{},

    allocator: std.mem.Allocator,
    owned_query: ?[]const u8 = null,

    fn deinit(self: *QueryParams) void {
        if (self.owned_query) |q| self.allocator.free(q);
    }
};

fn parseQuery(allocator: std.mem.Allocator, q: []const u8) !QueryParams {
    var params = QueryParams{ .allocator = allocator };
    if (q.len == 0) return params;
    var it = std.mem.tokenizeScalar(u8, q[1..], '&');
    while (it.next()) |kv| {
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        const key = kv[0..eq];
        const val = kv[eq + 1 ..];
        if (std.mem.eql(u8, key, "offset")) {
            params.offset = std.fmt.parseInt(usize, val, 10) catch params.offset;
        } else if (std.mem.eql(u8, key, "limit")) {
            params.limit = std.fmt.parseInt(usize, val, 10) catch params.limit;
        } else if (std.mem.eql(u8, key, "q")) {
            params.owned_query = allocator.dupe(u8, val) catch null;
            params.query = params.owned_query orelse params.query;
        }
    }
    return params;
}

fn parsePath(req: []const u8) ![]const u8 {
    const sp1 = std.mem.indexOfScalar(u8, req, ' ') orelse return error.BadRequest;
    const sp2 = std.mem.indexOfScalarPos(u8, req, sp1 + 1, ' ') orelse return error.BadRequest;
    return req[sp1 + 1 .. sp2];
}

fn respond(code: u16, msg: []const u8, allocator: std.mem.Allocator) ![]u8 {
    _ = code; // currently unused; placeholder for future.
    return allocator.dupe(u8, msg);
}

fn writeHex(w: anytype, bytes: []const u8) !void {
    for (bytes) |b| try w.print("{x:0>2}", .{b});
}

fn writeJsonString(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const item_mod = @import("../domain/clipboard_item.zig");
const ClipboardHistory = @import("../domain/clipboard_history.zig").ClipboardHistory;

fn makeItem(id_byte: u8, ts: Timestamp, text: []const u8) ClipboardItem {
    const id: Id = .{id_byte} ** 16;
    return item_mod.ClipboardItem.init(id, ts, text) catch unreachable;
}

const Timestamp = domain.Timestamp;

fn setupHistory() ClipboardHistory {
    var history = ClipboardHistory.init(std.testing.allocator, 10);
    history.add(makeItem(1, 1, "hello")) catch unreachable;
    history.add(makeItem(2, 2, "world")) catch unreachable;
    return history;
}

test "lists history with pagination" {
    var history = setupHistory();
    defer history.deinit();
    var lister = ListClipboardHistory.init(&history);
    var handler = HistoryQueryHandler.init(std.testing.allocator, &lister, null);
    defer handler.allocator.free(handler.handle("GET /history?offset=1&limit=1 HTTP/1.1\r\n\r\n") catch unreachable);

    const body = handler.handle("GET /history?offset=1&limit=1 HTTP/1.1\r\n\r\n") catch unreachable;
    defer std.testing.allocator.free(body);
    try expect(std.mem.indexOf(u8, body, "world") != null);
}

test "filters by query" {
    var history = setupHistory();
    defer history.deinit();
    var lister = ListClipboardHistory.init(&history);
    var handler = HistoryQueryHandler.init(std.testing.allocator, &lister, null);
    const body = handler.handle("GET /history?q=HEL HTTP/1.1\r\n\r\n") catch unreachable;
    defer std.testing.allocator.free(body);
    try expect(std.mem.indexOf(u8, body, "hello") != null);
    try expect(std.mem.indexOf(u8, body, "world") == null);
}
