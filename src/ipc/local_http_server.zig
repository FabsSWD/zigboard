const std = @import("std");

/// Minimal localhost-only HTTP server wrapper for IPC. Not production-hardened.
pub fn LocalHttpServer(comptime Handler: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        handler: Handler,
        server: std.net.Server,
        buf: []u8,
        running: bool = false,

        pub fn init(allocator: std.mem.Allocator, port: u16, handler: Handler) !Self {
            const addr = try std.net.Address.parseIp4("127.0.0.1", port);
            const server = try addr.listen(.{ .reuse_address = true });
            const buf = try allocator.alloc(u8, 16 * 1024);
            return .{
                .allocator = allocator,
                .handler = handler,
                .server = server,
                .buf = buf,
            };
        }

        pub fn deinit(self: *Self) void {
            self.server.deinit();
            self.allocator.free(self.buf);
        }

        pub fn start(self: *Self) void {
            self.running = true;
        }

        pub fn stop(self: *Self) void {
            self.running = false;
        }

        pub fn acceptOnce(self: *Self) !void {
            if (!self.running) return;

            var conn = try self.server.accept();
            defer conn.stream.close();

            const readn = try conn.stream.read(self.buf);
            const req = self.buf[0..readn];

            const body = try self.handler.handleRequest(req);
            defer self.allocator.free(body);

            const header = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n", .{body.len});
            defer self.allocator.free(header);
            _ = try conn.stream.write(header);
            _ = try conn.stream.write(body);
        }
    };
}

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const TestHandler = struct {
    allocator: std.mem.Allocator,
    last_req: []const u8 = &[_]u8{},

    pub fn handle(self: *TestHandler, req: []const u8) ![]const u8 {
        self.last_req = req;
        return try self.allocator.dupe(u8, "pong");
    }
};

test "serves single request" {
    var handler = TestHandler{ .allocator = std.testing.allocator };
    var server = try LocalHttpServer(*TestHandler).init(std.testing.allocator, 9800, &handler);
    defer server.deinit();
    server.start();

    var t = try std.Thread.spawn(.{}, acceptThread, .{&server});
    defer t.join();

    const addr = try std.net.Address.parseIp4("127.0.0.1", 9800);
    var conn = try std.net.tcpConnectToAddress(addr);
    defer conn.close();

    try conn.writer().writeAll("GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n");
    var resp_buf: [128]u8 = undefined;
    const got = try conn.reader().readAll(&resp_buf);

    try expect(std.mem.indexOf(u8, resp_buf[0..got], "pong") != null);
    try expectEqual(@as(usize, "GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n".len), handler.last_req.len);
}

fn acceptThread(server: *LocalHttpServer(*TestHandler)) void {
    server.acceptOnce() catch unreachable;
}
