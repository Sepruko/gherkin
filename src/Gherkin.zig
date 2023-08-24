//! This struct is a memory-managed wrapper for `gherkin.GherkinUnmanaged`. If
//! you'd like to know more about how to use it, view the documentation for that
//! type instead.
//!
//! For reference, this is to `gherkin.GherkinUnmanaged` like `std.ArrayList` is
//! to `std.ArrayListUnmanaged`.

const Gherkin = @This();

const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const FixedBufferAllocator = heap.FixedBufferAllocator;

const GherkinIterator = @import("GherkinIterator.zig");
const GherkinUnmanaged = @import("GherkinUnmanaged.zig");

/// The held `GherkinUnmanaged` that this `Gherkin` wraps. This value will have
/// its appropriate methods called with `.allocator` passed in automatically.
unmanaged: GherkinUnmanaged,

/// The allocator that is kept and used by this `Gherkin` for automatically
/// passing to `.unmanaged`'s methods.
allocator: Allocator,

/// An alias to `GherkinUnmanaged`'s public type of the same name.
pub const InnerList = ArrayListUnmanaged(u8);

/// Options for customizing the resulting `Gherkin` from `.init`.
pub const Options = @Type(.{ .Struct = .{
    .layout = .Auto,
    .fields = meta.fields(struct {
        unmanaged: ?GherkinUnmanaged = null,
    }) ++ meta.fields(GherkinUnmanaged.Options),
    .decls = &[_]std.builtin.Type.Declaration{},
    .is_tuple = false,
} });

/// Create a new `Gherkin` as per the provided options. The passed
/// `std.mem.Allocator` is used for allocating the initial space required by
/// `options.header_size` and throughout the life of the `Gherkin`.
///
/// This method will `@panic` if the provided `options.header_size` cannot fit a
/// `u32` (assumes developer error).
pub fn init(allocator: Allocator, options: Options) Allocator.Error!Gherkin {
    var inner_opts: *GherkinUnmanaged.Options = @ptrFromInt(
        @intFromPtr(&options) + @offsetOf(Options, meta.fields(GherkinUnmanaged.Options)[0].name),
    );

    return .{
        .unmanaged = options.unmanaged orelse try GherkinUnmanaged.init(allocator, inner_opts.*),
        .allocator = allocator,
    };
}

/// Deinitialize the `Gherkin`, freeing the allocated pickled memory.
pub fn deinit(self: *Gherkin) void {
    self.unmanaged.deinit(self.allocator);
    self.* = undefined;
}

/// Creates a new `GherkinIterator` from the target `GherkinUnmanaged`.
///
/// Be careful that growing the internal buffer of the `GherkinUnmanaged` will
/// invalidate the pointer passed to the returned `GherkinIterator`, making it
/// unsafe to read from.
pub inline fn iterator(self: Gherkin) GherkinIterator {
    return GherkinIterator.init(self.unmanaged.inner_list.items);
}

/// Convert this `Gherkin` into a `GherkinUnmanaged`, and it will no-longer be
/// safe to call `.deinit` on the donor `Gherkin`.
pub fn moveToUnmanaged(self: *Gherkin) GherkinUnmanaged {
    const unmanaged = self.unmanaged;
    self.* = undefined;

    return unmanaged;
}

/// Initialize a new `Gherkin` with ownership of the passed `slice`. The same
/// `allocator` that allocated the `slice` must be passed.
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn fromOwnedSlice(allocator: Allocator, slice: []u8) Gherkin {
    return .{
        .unmanaged = GherkinUnmanaged.fromOwnedSlice(slice),
        .allocator = allocator,
    };
}

/// Initialize a new `Gherkin` with ownership of the passed `slice` (with a
/// sentinel). The same `allocator` that allocated the `slice` must also be
/// passed.
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn fromOwnedSliceSentinel(
    allocator: Allocator,
    comptime sentinel: u8,
    slice: [:sentinel]u8,
) Gherkin {
    return .{
        .unmanaged = GherkinUnmanaged.fromOwnedSliceSentinel(sentinel, slice),
        .allocator = allocator,
    };
}

/// Claim the internal memory buffer from the `Gherkin`. It will no-longer be
/// safe to call `.deinit` on the `Gherkin`.
pub fn toOwnedSlice(self: *Gherkin) Allocator.Error![]u8 {
    defer self.* = undefined;
    return self.unmanaged.toOwnedSlice(self.allocator);
}

/// Claim the internal memory buffer (with a sentinel) from the `Gherkin`. It
/// will no-longer be safe to call `.deinit` on the `Gherkin`.
pub fn toOwnedSliceSentinel(
    self: *Gherkin,
    comptime sentinel: u8,
) Allocator.Error![:sentinel]u8 {
    defer self.* = undefined;
    return self.unmanaged.toOwnedSliceSentinel(self.allocator, sentinel);
}

/// Create a clone of the `Gherkin`.
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn clone(self: Gherkin) Allocator.Error!Gherkin {
    return .{
        .unmanaged = try self.unmanaged.clone(self.allocator),
        .allocator = self.allocator,
    };
}

/// Write a pickled value with a simple type to the internal memory buffer.
///
/// See the documentation for `gherkin.GherkinUnmanaged.write` on which types
/// may be pickled.
pub inline fn write(self: *Gherkin, comptime T: type, value: T) Allocator.Error!usize {
    return self.unmanaged.write(self.allocator, T, value);
}

/// Write a pickled many-item pointer to the internal memory buffer.
///
/// See the documentation for `gherkin.GherkinUnmanaged.write` on which types
/// may be pickled.
pub inline fn writeMany(
    self: *Gherkin,
    comptime T: type,
    ptr: [*]const T,
    len: usize,
) Allocator.Error!usize {
    return self.unmanaged.writeMany(self.allocator, T, ptr, len);
}

/// Write a pickled many-item pointer (with a sentinel) to the internal memory
/// buffer.
///
/// See the documentation for `gherkin.GherkinUnmanaged.write` on which types
/// may be pickled.
pub inline fn writeManySentinel(
    self: *Gherkin,
    comptime T: type,
    comptime sentinel: T,
    ptr: [*:sentinel]const T,
    len: usize,
) Allocator.Error!usize {
    return self.unmanaged.writeMany(self.allocator, T, ptr, len + 1);
}

test "gherkin.Gherkin/Gherkin.moveToUnmanaged" {
    var gherkin = try init(testing.allocator, .{});

    const @"expected_[]const u8" = "foobar";
    _ = try gherkin.write([]const u8, @"expected_[]const u8");

    var unmanaged_gherkin = gherkin.moveToUnmanaged();
    defer unmanaged_gherkin.deinit(testing.allocator);

    try testing.expectEqualStrings(
        // 11 ++ 6 ++ @"expected_[]const u8"
        "\x0e\x00\x00\x00" ++ "\x06\x00\x00\x00" ++ @"expected_[]const u8",
        unmanaged_gherkin.inner_list.items,
    );
}

test "gherkin.Gherkin/Gherkin.fromOwnedSlice" {
    var slice = try testing.allocator.dupe(u8, "foobar");

    var gherkin = fromOwnedSlice(testing.allocator, slice);
    defer gherkin.deinit();

    // Compare pointers as no re-slicing occurs.
    try testing.expectEqual(slice, gherkin.unmanaged.inner_list.items);
}

test "gherkin.Gherkin/Gherkin.fromOwnedSliceSentinel" {
    var slice_z = try testing.allocator.dupeZ(u8, "foobar");

    var gherkin = fromOwnedSliceSentinel(testing.allocator, 0, slice_z);
    defer gherkin.deinit();

    // Compare contents as re-slicing occurs internally.
    try testing.expectEqualStrings(slice_z, gherkin.unmanaged.inner_list.items);
}

test "gherkin.Gherkin/Gherkin.toOwnedSlice" {
    var gherkin = try init(testing.allocator, .{});

    const @"expected_[]const u8" = "foobar";
    _ = try gherkin.write([]const u8, @"expected_[]const u8");

    var owned_slice = try gherkin.toOwnedSlice();
    defer testing.allocator.free(owned_slice);

    try testing.expectEqualStrings(
        // 11 ++ 6 ++ @"expected_[]const u8"
        "\x0e\x00\x00\x00" ++ "\x06\x00\x00\x00" ++ @"expected_[]const u8",
        owned_slice,
    );
}

test "gherkin.Gherkin/Gherkin.toOwnedSliceSentinel" {
    var gherkin = try init(testing.allocator, .{});

    const @"expected_[]const u8" = "foobar";
    _ = try gherkin.write([]const u8, @"expected_[]const u8");

    var owned_slice_z = try gherkin.toOwnedSliceSentinel(0);
    defer testing.allocator.free(owned_slice_z);

    try testing.expectEqualStrings(
        // 11 ++ 6 ++ @"expected_[]const u8" ++ 0
        "\x0e\x00\x00\x00" ++ "\x06\x00\x00\x00" ++ @"expected_[]const u8" ++ "\x00",
        // Include sentinel, or get an out-of-bounds error meaning we did
        // something wrong.
        owned_slice_z[0 .. owned_slice_z.len + 1],
    );
}

test "gherkin.Gherkin/Gherkin.clone" {
    var gherkin = try init(testing.allocator, .{});
    defer gherkin.deinit();

    var gherkin_clone = try gherkin.clone();
    defer gherkin_clone.deinit();

    try testing.expect(
        gherkin.unmanaged.inner_list.items.ptr !=
            gherkin_clone.unmanaged.inner_list.items.ptr,
    );
    try testing.expectEqualStrings(
        gherkin.unmanaged.inner_list.items,
        gherkin_clone.unmanaged.inner_list.items,
    );
}

test "gherkin.Gherkin/Gherkin.write -> .Float" {
    var gherkin = try init(testing.allocator, .{});
    defer gherkin.deinit();

    const size_f32: usize = @sizeOf(f32);
    const IntFloat32 = meta.Int(.unsigned, @as(u16, @truncate(size_f32)) * @bitSizeOf(u8));
    const expected_f32: f32 = 13.37;

    _ = try gherkin.write(f32, expected_f32);
    const index_f32 = gherkin.unmanaged.inner_list.items.len - size_f32;

    const result_f32 = @as(*const f32, @ptrCast(&mem.readIntLittle(IntFloat32, @as(
        *const [size_f32]u8,
        @ptrCast(gherkin.unmanaged.inner_list.items[index_f32 .. index_f32 + size_f32].ptr),
    )))).*;
    try testing.expectEqual(expected_f32, result_f32);

    const size_f80: usize = @sizeOf(f80);
    const IntFloat80 = meta.Int(.unsigned, @as(u16, @truncate(size_f80)) * @bitSizeOf(u8));
    const expected_f80: f80 = 80.08;

    _ = try gherkin.write(f80, expected_f80);
    const index_f80 = gherkin.unmanaged.inner_list.items.len - size_f80;

    const result_f80 = @as(*align(1) const f80, @ptrCast(&mem.readIntLittle(IntFloat80, @as(
        *const [size_f80]u8,
        @ptrCast(gherkin.unmanaged.inner_list.items[index_f80 .. index_f80 + size_f80].ptr),
    )))).*;
    try testing.expectEqual(expected_f80, result_f80);
}
