const std = @import("std");
const posix = std.posix;
const CInt = std.c_int;

const TickFn = fn (*anyopaque) anyerror!void;
const StartFn = fn (*anyopaque) anyerror!void;
const StopFn = fn (*anyopaque) void;

pub const DaemonOptions = struct {
    tick: ?TickFn = null,
    on_start: ?StartFn = null,
    on_stop: ?StopFn = null,
    ctx: ?*anyopaque = null,
    idle_ns: u64 = 10 * std.time.ns_per_ms,
};

pub const Daemon = struct {
    allocator: std.mem.Allocator,
    opts: DaemonOptions,
    running: bool = false,
    stop_requested: bool = false,
    prev_int: posix.Sigaction = undefined,
    prev_term: posix.Sigaction = undefined,
    installed_handlers: bool = false,

    pub fn init(allocator: std.mem.Allocator, opts: DaemonOptions) Daemon {
        return .{ .allocator = allocator, .opts = opts };
    }

    pub fn run(self: *Daemon) !void {
        if (self.running) return error.AlreadyRunning;
        self.running = true;
        self.stop_requested = false;
        stop_flag.store(false, .SeqCst);
        try self.installHandlers();
        defer self.restoreHandlers();

        if (self.opts.on_start) |f| try f(self.opts.ctx orelse null);

        while (!self.shouldStop()) {
            if (self.opts.tick) |tick_fn| {
                try tick_fn(self.opts.ctx orelse null);
            } else {
                std.time.sleep(self.opts.idle_ns);
            }
        }

        if (self.opts.on_stop) |f| f(self.opts.ctx orelse null);
        self.running = false;
    }

    pub fn stop(self: *Daemon) void {
        self.stop_requested = true;
    }

    fn shouldStop(self: *Daemon) bool {
        return self.stop_requested or stop_flag.load(.SeqCst);
    }

    fn installHandlers(self: *Daemon) !void {
        var action = posix.Sigaction{
            .handler = .{ .handler = handleSignal },
            .mask = posix.empty_sigset,
            .flags = 0,
            .restorer = null,
        };
        try posix.sigaction(posix.SIG.INT, &action, &self.prev_int);
        try posix.sigaction(posix.SIG.TERM, &action, &self.prev_term);
        self.installed_handlers = true;
    }

    fn restoreHandlers(self: *Daemon) void {
        if (!self.installed_handlers) return;
        posix.sigaction(posix.SIG.INT, &self.prev_int, null) catch {};
        posix.sigaction(posix.SIG.TERM, &self.prev_term, null) catch {};
        self.installed_handlers = false;
    }
};

var stop_flag = std.atomic.Value(bool).init(false);

fn handleSignal(sig: CInt) callconv(.C) void {
    _ = sig;
    stop_flag.store(true, .SeqCst);
}

const expect = std.testing.expect;

const Ctx = struct {
    ticks: usize = 0,
    stopped: bool = false,
};

fn tick(ctx_ptr: *anyopaque) !void {
    const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr));
    ctx.ticks += 1;
    std.time.sleep(1000);
}

fn onStop(ctx_ptr: *anyopaque) void {
    const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr));
    ctx.stopped = true;
}

fn runThread(d: *Daemon) void {
    d.run() catch unreachable;
}

test "stop exits loop" {
    var ctx = Ctx{};
    var daemon = Daemon.init(std.testing.allocator, .{ .tick = tick, .on_stop = onStop, .ctx = &ctx, .idle_ns = 1_000 });
    var t = try std.Thread.spawn(.{}, runThread, .{&daemon});
    std.time.sleep(5 * std.time.ns_per_ms);
    daemon.stop();
    t.join();
    try expect(ctx.stopped);
    try expect(ctx.ticks > 0);
}

test "signal triggers shutdown" {
    var ctx = Ctx{};
    var daemon = Daemon.init(std.testing.allocator, .{ .tick = tick, .on_stop = onStop, .ctx = &ctx, .idle_ns = 1_000 });
    var t = try std.Thread.spawn(.{}, runThread, .{&daemon});
    std.time.sleep(5 * std.time.ns_per_ms);
    posix.raise(posix.SIG.INT) catch unreachable;
    t.join();
    try expect(ctx.stopped);
}
