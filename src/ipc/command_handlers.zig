const std = @import("std");
const domain = @import("../lib.zig").domain;
const PinClipboardEntry = @import("../application/pin_clipboard_entry.zig").PinClipboardEntry;
const DeleteClipboardEntry = @import("../application/delete_clipboard_entry.zig").DeleteClipboardEntry;

const Id = domain.Id;
const ClipboardHistory = domain.ClipboardHistory;

/// Command handler for pin/unpin/delete operations.
pub const CommandHandler = struct {
    allocator: std.mem.Allocator,
    history: *ClipboardHistory,
    pinner: *PinClipboardEntry,
    deleter: *DeleteClipboardEntry,

    pub fn init(allocator: std.mem.Allocator, history: *ClipboardHistory, pinner: *PinClipboardEntry, deleter: *DeleteClipboardEntry) CommandHandler {
        return .{ .allocator = allocator, .history = history, .pinner = pinner, .deleter = deleter };
    }

    pub fn handle(self: *CommandHandler, req: []const u8) ![]const u8 {
        const parsed = parseRequest(req) catch return respondError(self.allocator, "bad request");
        const path = parsed.path;

        if (std.mem.startsWith(u8, path, "/pin")) {
            if (!std.mem.eql(u8, parsed.method, "POST")) return respondError(self.allocator, "method not allowed");
            return self.pin(path);
        }
        if (std.mem.startsWith(u8, path, "/unpin")) {
            if (!std.mem.eql(u8, parsed.method, "POST")) return respondError(self.allocator, "method not allowed");
            return self.unpin(path);
        }
        if (std.mem.startsWith(u8, path, "/delete")) {
            if (!std.mem.eql(u8, parsed.method, "DELETE")) return respondError(self.allocator, "method not allowed");
            return self.delete(path);
        }
        return respondError(self.allocator, "not found");
    }

    fn pin(self: *CommandHandler, path: []const u8) ![]const u8 {
        const id = parseIdParam(path) catch |err| return respondError(self.allocator, errMsg(err));
        if (!contains(self.history, id)) return respondError(self.allocator, "id not found");
        self.pinner.pin(id) catch return respondError(self.allocator, "internal error");
        return respondOk(self.allocator, "pinned");
    }

    fn unpin(self: *CommandHandler, path: []const u8) ![]const u8 {
        const id = parseIdParam(path) catch |err| return respondError(self.allocator, errMsg(err));
        if (!contains(self.history, id)) return respondError(self.allocator, "id not found");
        if (!self.pinner.unpin(id)) return respondError(self.allocator, "not pinned");
        return respondOk(self.allocator, "unpinned");
    }

    fn delete(self: *CommandHandler, path: []const u8) ![]const u8 {
        const id = parseIdParam(path) catch |err| return respondError(self.allocator, errMsg(err));
        self.deleter.execute(id) catch |err| {
            if (err == error.EntryNotFound) return respondError(self.allocator, "id not found");
            return respondError(self.allocator, "internal error");
        };
        _ = self.pinner.unpin(id);
        return respondOk(self.allocator, "deleted");
    }
};

const RequestLine = struct { method: []const u8, path: []const u8 };

fn parseRequest(req: []const u8) !RequestLine {
    const sp1 = std.mem.indexOfScalar(u8, req, ' ') orelse return error.BadRequest;
    const sp2 = std.mem.indexOfScalarPos(u8, req, sp1 + 1, ' ') orelse return error.BadRequest;
    const method = req[0..sp1];
    const path = req[sp1 + 1 .. sp2];
    if (method.len == 0 or path.len == 0 or path[0] != '/') return error.BadRequest;
    return .{ .method = method, .path = path };
}

fn parseIdParam(path: []const u8) !Id {
    const q = std.mem.indexOfScalar(u8, path, '?') orelse return error.MissingId;
    var it = std.mem.tokenizeScalar(u8, path[q + 1 ..], '&');
    while (it.next()) |kv| {
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        const key = kv[0..eq];
        if (!std.mem.eql(u8, key, "id")) continue;
        const hex = kv[eq + 1 ..];
        return parseHexId(hex);
    }
    return error.MissingId;
}

fn parseHexId(hex: []const u8) !Id {
    if (hex.len != 32) return error.InvalidIdLength;
    var id: Id = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const idx = i * 2;
        id[i] = std.fmt.parseInt(u8, hex[idx .. idx + 2], 16) catch return error.InvalidHex;
    }
    return id;
}

fn contains(history: *ClipboardHistory, id: Id) bool {
    for (history.slice()) |it| if (std.mem.eql(u8, &it.id, &id)) return true;
    return false;
}

fn respondOk(allocator: std.mem.Allocator, status: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"status\":\"{s}\"}}", .{status});
}

fn respondError(allocator: std.mem.Allocator, msg: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{msg});
}

fn errMsg(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingId => "missing id",
        error.InvalidIdLength => "id must be 32 hex chars",
        error.InvalidHex => "invalid id hex",
        else => "bad request",
    };
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const item_mod = @import("../domain/clipboard_item.zig");
const ClipboardItem = item_mod.ClipboardItem;

fn makeItem(b: u8, ts: i128, text: []const u8) ClipboardItem {
    const id: Id = .{b} ** 16;
    return ClipboardItem.init(id, ts, text) catch unreachable;
}

fn setup(history: *ClipboardHistory) void {
    history.* = ClipboardHistory.init(std.testing.allocator, 4);
    history.add(makeItem(1, 1, "one")) catch unreachable;
}

test "pins valid id" {
    var history: ClipboardHistory = undefined;
    setup(&history);
    defer history.deinit();

    var pinner = PinClipboardEntry.init(std.testing.allocator);
    defer pinner.deinit();
    var deleter = DeleteClipboardEntry.init(&history);
    var handler = CommandHandler.init(std.testing.allocator, &history, &pinner, &deleter);

    const res = handler.handle("POST /pin?id=01010101010101010101010101010101 HTTP/1.1\r\n\r\n") catch unreachable;
    defer std.testing.allocator.free(res);
    try expect(pinner.isPinned(.{1} ** 16));
    try expectEqualStrings("{\"ok\":true,\"status\":\"pinned\"}", res);
}

test "rejects invalid hex" {
    var history: ClipboardHistory = undefined;
    setup(&history);
    defer history.deinit();

    var pinner = PinClipboardEntry.init(std.testing.allocator);
    defer pinner.deinit();
    var deleter = DeleteClipboardEntry.init(&history);
    var handler = CommandHandler.init(std.testing.allocator, &history, &pinner, &deleter);

    const res = handler.handle("POST /pin?id=zz HTTP/1.1\r\n\r\n") catch unreachable;
    defer std.testing.allocator.free(res);
    try expectEqualStrings("{\"error\":\"id must be 32 hex chars\"}", res);
}

test "deletes and unpins" {
    var history: ClipboardHistory = undefined;
    setup(&history);
    defer history.deinit();

    var pinner = PinClipboardEntry.init(std.testing.allocator);
    defer pinner.deinit();
    var deleter = DeleteClipboardEntry.init(&history);
    var handler = CommandHandler.init(std.testing.allocator, &history, &pinner, &deleter);

    _ = pinner.pin(.{1} ** 16);
    const res = handler.handle("DELETE /delete?id=01010101010101010101010101010101 HTTP/1.1\r\n\r\n") catch unreachable;
    defer std.testing.allocator.free(res);
    try expect(!pinner.isPinned(.{1} ** 16));
    try expectEqualStrings("{\"ok\":true,\"status\":\"deleted\"}", res);
    try expect(history.len() == 0);
}
