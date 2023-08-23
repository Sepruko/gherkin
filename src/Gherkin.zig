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

    _ = try gherkin.write([]const u8, "foobar");

    var copy = try testing.allocator.dupe(u8, gherkin.unmanaged.inner_list.items);
    defer testing.allocator.free(copy);

    var unmanaged_gherkin = gherkin.moveToUnmanaged();
    defer unmanaged_gherkin.deinit(testing.allocator);

    try testing.expectEqualStrings(copy, unmanaged_gherkin.inner_list.items);
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

    _ = try gherkin.write([]const u8, "foobar");

    var copy = try testing.allocator.dupe(u8, gherkin.unmanaged.inner_list.items);
    defer testing.allocator.free(copy);

    var owned_slice = try gherkin.toOwnedSlice();
    defer testing.allocator.free(owned_slice);

    try testing.expectEqualStrings(copy, owned_slice);
}

test "gherkin.Gherkin/Gherkin.toOwnedSliceSentinel" {
    var gherkin = try init(testing.allocator, .{});

    _ = try gherkin.write([]const u8, "foobar");

    var copy_z = try testing.allocator.dupeZ(u8, gherkin.unmanaged.inner_list.items);
    defer testing.allocator.free(copy_z);

    var owned_slice_z = try gherkin.toOwnedSliceSentinel(0);
    defer testing.allocator.free(owned_slice_z);

    try testing.expectEqualStrings(copy_z, owned_slice_z);
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
    var gherkin_32 = try init(testing.allocator, .{});
    defer gherkin_32.deinit();

    _ = try gherkin_32.write(f32, 13.37);

    const Int32 = meta.Int(.unsigned, @sizeOf(f32) * 8);
    const float_32 = @as(*const f32, (@ptrCast(&mem.readIntLittle(
        Int32,
        gherkin_32.unmanaged.inner_list.items[@sizeOf(u32) .. @sizeOf(u32) + @sizeOf(Int32)],
    )))).*;

    _ = try testing.expectEqual(@as(f32, 13.37), float_32);

    var gherkin_80 = try init(testing.allocator, .{});
    defer gherkin_80.deinit();

    _ = try gherkin_80.write(f80, 80.08);

    const Int80 = meta.Int(.unsigned, @sizeOf(f80) * 8);
    const float_80 = @as(*align(4) const f80, (@ptrCast(&mem.readIntLittle(
        Int80,
        gherkin_80.unmanaged.inner_list.items[@sizeOf(u32) .. @sizeOf(u32) + @sizeOf(Int80)],
    )))).*;

    _ = try testing.expectEqual(@as(f80, 80.08), float_80);
}
