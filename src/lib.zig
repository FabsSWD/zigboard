pub const domain = struct {
    const item = @import("domain/clipboard_item.zig");
    const session = @import("domain/session.zig");
    const history = @import("domain/clipboard_history.zig");

    pub const Id = item.Id;
    pub const Timestamp = item.Timestamp;
    pub const ClipboardItem = item.ClipboardItem;
    pub const Session = session.Session;
    pub const ClipboardHistory = history.ClipboardHistory;
};

pub const application = struct {
    pub const AddClipboardEntry = @import("application/add_clipboard_entry.zig").AddClipboardEntry;
    pub const ListClipboardHistory = @import("application/list_clipboard_history.zig").ListClipboardHistory;
    pub const PinClipboardEntry = @import("application/pin_clipboard_entry.zig").PinClipboardEntry;
};
pub const DeleteClipboardEntry = @import("application/delete_clipboard_entry.zig").DeleteClipboardEntry;

pub const adapters = struct {
    pub const LinuxClipboard = @import("adapters/linux_clipboard.zig").LinuxClipboard;
};
