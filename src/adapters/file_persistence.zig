const std = @import("std");
const domain = @import("../lib.zig").domain;

const ClipboardItem = domain.ClipboardItem;
const Id = domain.Id;
const Timestamp = domain.Timestamp;

pub const FilePersistence = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) FilePersistence {
        return .{
            .allocator = allocator,
            .file_path = file_path,
        };
    }

    pub fn save(self: *FilePersistence, items: []const ClipboardItem) !void {
        const file = try std.fs.cwd().createFile(self.file_path, .{});
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        try writer.writeAll("[\n");
        for (items, 0..) |item, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("  {\"id\":\"");
            try writeHex(writer, &item.id);
            try writer.writeAll("\",\"ts\":");
            try writer.print("{d}", .{item.created_at});
            try writer.writeAll(",\"text\":\"");
            try writeJsonString(writer, item.payload);
            try writer.writeAll("\"}");
        }
        try writer.writeAll("\n]\n");
        try buffered.flush();
    }

    pub fn load(self: *FilePersistence) !std.ArrayList(ClipboardItem) {
        const file = std.fs.cwd().openFile(self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return std.ArrayList(ClipboardItem).init(self.allocator);
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var items = std.ArrayList(ClipboardItem).init(self.allocator);
        errdefer items.deinit();

        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();

        const tree = try parser.parse(content);
        defer tree.deinit();

        const root = tree.root.array;
        for (root.items) |obj_node| {
            const obj = obj_node.object;
            const id_hex = obj.get("id").?.string;
            const ts = @as(Timestamp, @intCast(obj.get("ts").?.integer));
            const text = obj.get("text").?.string;

            var id: Id = undefined;
            try parseHex(id_hex, &id);

            const text_copy = try self.allocator.dupe(u8, text);
            errdefer self.allocator.free(text_copy);

            const item = try ClipboardItem.init(id, ts, text_copy);
            try items.append(item);
        }

        return items;
    }

    fn writeHex(writer: anytype, bytes: []const u8) !void {
        for (bytes) |b| {
            try writer.print("{x:0>2}", .{b});
        }
    }

    fn parseHex(hex: []const u8, out: *Id) !void {
        if (hex.len != 32) return error.InvalidHexLength;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            out[i] = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
        }
    }

    fn writeJsonString(writer: anytype, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
    }
};

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn makeItem(id_byte: u8, ts: Timestamp, text: []const u8) ClipboardItem {
    const id: Id = .{id_byte} ** 16;
    return ClipboardItem.init(id, ts, text) catch unreachable;
}

test "save and load round-trip" {
    const path = "test_persistence.json";
    defer std.fs.cwd().deleteFile(path) catch {};

    var persist = FilePersistence.init(std.testing.allocator, path);

    const items = [_]ClipboardItem{
        makeItem(1, 100, "hello"),
        makeItem(2, 200, "world"),
    };

    try persist.save(&items);

    var loaded = try persist.load();
    defer {
        for (loaded.items) |item| {
            std.testing.allocator.free(item.payload);
        }
        loaded.deinit();
    }

    try expectEqual(@as(usize, 2), loaded.items.len);
    try expectEqualStrings("hello", loaded.items[0].text());
    try expectEqual(@as(Timestamp, 100), loaded.items[0].createdAt());
}

test "load returns empty list when file missing" {
    var persist = FilePersistence.init(std.testing.allocator, "nonexistent.json");
    var loaded = try persist.load();
    defer loaded.deinit();

    try expectEqual(@as(usize, 0), loaded.items.len);
}
