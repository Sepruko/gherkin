const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const Allocator = mem.Allocator;
const GherkinUnmanaged = @import("GherkinUnmanaged.zig");

unmanaged: GherkinUnmanaged,
allocator: Allocator,

const Gherkin = @This();

pub const InnerList = GherkinUnmanaged.InnerList;

pub const Options = @Type(.{ .Struct = .{
    .layout = .Auto,
    .fields = meta.fields(struct {
        unmanaged: ?GherkinUnmanaged = null,
    }) ++ meta.fields(GherkinUnmanaged.Options),
    .decls = &[_]std.builtin.Type.Declaration{},
    .is_tuple = false,
} });

pub fn init(allocator: Allocator, options: Options) Allocator.Error!Gherkin {
    var unmanaged_options_ptr = @as(
        *GherkinUnmanaged.Options,
        @ptrFromInt(@intFromPtr(&options) + @offsetOf(
            Options,
            meta.fields(GherkinUnmanaged.Options)[0].name,
        )),
    );

    return .{
        .unmanaged = options.unmanaged orelse try GherkinUnmanaged.init(
            allocator,
            unmanaged_options_ptr.*,
        ),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Gherkin) void {
    self.unmanaged.deinit(self.allocator);
    self.* = undefined;
}

pub fn moveToUnmanaged(self: *Gherkin) Allocator.Error!GherkinUnmanaged {
    const unmanaged = self.unmanaged;
    self.* = try init(self.allocator, .{});

    return unmanaged;
}

pub fn fromOwnedSlice(allocator: Allocator, slice: []u8) Gherkin {
    return .{
        .unmanaged = GherkinUnmanaged.fromOwnedSlice(slice),
        .allocator = allocator,
    };
}

pub inline fn fromOwnedSliceSentinel(
    allocator: Allocator,
    comptime sentinel: u8,
    slice: [:sentinel]u8,
) Gherkin {
    return .{
        .unmanaged = GherkinUnmanaged.fromOwnedSliceSentinel(sentinel, slice),
        .allocator = allocator,
    };
}

pub inline fn toOwnedSlice(self: *Gherkin) Allocator.Error![]u8 {
    return self.unmanaged.toOwnedSlice(self.allocator);
}

pub inline fn toOwnedSliceSentinel(
    self: *GherkinUnmanaged,
    comptime sentinel: u8,
) Allocator.Error![]u8 {
    return self.toOwnedSlice(self.allocator)[0.. :sentinel];
}

pub fn clone(self: Gherkin) Allocator.Error!Gherkin {
    return .{
        .unmanaged = try self.unmanaged.clone(self.allocator),
        .allocator = self.allocator,
    };
}

pub inline fn write(self: *Gherkin, comptime T: type, value: T) Allocator.Error!usize {
    return self.unmanaged.write(self.allocator, T, value);
}

pub inline fn writeMany(
    self: *Gherkin,
    comptime T: type,
    ptr: [*]const T,
    len: usize,
) Allocator.Error!usize {
    return self.unmanaged.writeMany(self.allocator, T, ptr, len);
}

pub inline fn writeManySentinel(
    self: *Gherkin,
    comptime T: type,
    comptime sentinel: T,
    ptr: [*:sentinel]const T,
    len: usize,
) Allocator.Error!usize {
    return self.writeMany(T, ptr, len + 1);
}
