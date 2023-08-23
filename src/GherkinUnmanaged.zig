//! This struct can be used to create 'pickled' memory of simple types. If you'd
//! like to know more about which value types are supported, check the `.write`
//! method.
//!
//! The same `std.mem.Allocator` must be used throughout the lifetime of a
//! `GherkinUnmanaged`.
//!
//! This struct is a recreation of
//! [`pickle.h`](https://chromium.googlesource.com/chromium/src/+/main/base/pickle.h)
//! in Zig, it takes no reference from `pickle.cc`.

const GherkinUnmanaged = @This();

const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const FixedBufferAllocator = heap.FixedBufferAllocator;

const Gherkin = @import("Gherkin.zig");

/// The internal `std.ArrayListUnmanaged` used for automatically growing memory
/// as-required.
inner_list: InnerList,

/// An alias to the result of the generic function `ArrayListUnmanaged`, this is
/// used due to type changes in Zig's 0.11.0 release.
pub const InnerList = ArrayListUnmanaged(u8);

/// Options for customizing the resulting `GherkinUnmanaged` from `.init`.
pub const Options = struct {
    /// The starting header size of the pickled memory.
    header_size: u32 = @sizeOf(u32),
};

/// Create a new `GherkinUnmanaged` as per the provided options. The passed
/// `std.mem.Allocator` is used for allocating the initial space required by
/// `options.header_size`.
///
/// This method will `@panic` if the provided `options.header_size` cannot fit a
/// `u32` (assumes developer error).
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn init(allocator: Allocator, options: Options) Allocator.Error!GherkinUnmanaged {
    if (options.header_size < @sizeOf(u32))
        @panic("Provided options.header_size is too small to fit @sizeOf(u32)");

    var inner_list = try InnerList.initCapacity(
        allocator,
        @as(usize, @intCast(options.header_size)),
    );

    mem.writeIntLittle(
        u32,
        inner_list.addManyAsArrayAssumeCapacity(@sizeOf(u32)),
        options.header_size,
    );

    return .{ .inner_list = inner_list };
}

/// Deinitialize the `GherkinUnmanaged`, freeing the allocated pickled memory.
pub fn deinit(self: *GherkinUnmanaged, allocator: Allocator) void {
    self.inner_list.deinit(allocator);
    self.* = undefined;
}

/// Convert this `GherkinUnmanaged` into a `Gherkin`, and it will no-longer be
/// safe to call `.deinit` on the donor `GherkinUnmanaged`.
pub fn toManaged(self: *GherkinUnmanaged, allocator: Allocator) Gherkin {
    defer self.* = undefined;
    return .{
        .unmanaged = self.*,
        .allocator = allocator,
    };
}

/// Initialize a new `GherkinUnmanaged` with ownership of the passed `slice`.
/// The same `allocator` that allocated the `slice` must also be used throughout
/// the lifetime of this `GherkinUnmanaged`.
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn fromOwnedSlice(slice: []u8) GherkinUnmanaged {
    return .{
        .inner_list = InnerList.fromOwnedSlice(slice),
    };
}

/// Initialize a new `GherkinUnmanaged` with ownership of the passed `slice`
/// (with a sentinel). The same `allocator` that allocated the `slice` must also
/// be used throughout the lifetime of this `GherkinUnmanaged`.
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn fromOwnedSliceSentinel(comptime sentinel: u8, slice: [:sentinel]u8) GherkinUnmanaged {
    return .{
        .inner_list = InnerList.fromOwnedSliceSentinel(sentinel, slice),
    };
}

/// Claim the internal memory buffer from the `GherkinUnmanaged`. It will
/// no-longer be safe to call `.deinit` on the `GherkinUnmanaged`.
pub fn toOwnedSlice(self: *GherkinUnmanaged, allocator: Allocator) Allocator.Error![]u8 {
    defer self.deinit(allocator);
    return self.inner_list.toOwnedSlice(allocator);
}

/// Claim the internal memory buffer (with sentinel) from the
/// `GherkinUnmanaged`. It will no-longer be safe to call `.deinit` on the
/// `GherkinUnmanaged`.
pub fn toOwnedSliceSentinel(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime sentinel: u8,
) Allocator.Error![:sentinel]u8 {
    defer self.deinit(allocator);
    return self.inner_list.toOwnedSliceSentinel(allocator, sentinel);
}

/// Create a clone of the `GherkinUnmanaged`.
///
/// Deinitialize with `.deinit`, `.toOwnedSlice`, or `.toOwnedSliceSentinel`.
pub fn clone(self: GherkinUnmanaged, allocator: Allocator) Allocator.Error!GherkinUnmanaged {
    return .{
        .inner_list = try self.inner_list.clone(allocator),
    };
}

/// Internal method to easily get the current `header_size` of the pickled
/// memory buffer.
inline fn getHeaderSize(self: GherkinUnmanaged) u32 {
    return mem.readIntLittle(u32, self.inner_list.items[0..@sizeOf(u32)]);
}

/// Internal method to easily set the current `header_size` of the pickled
/// memory buffer.
///
/// This method will not resize the buffer, whether in indexable memory or total
/// capacity.
inline fn setHeaderSize(self: GherkinUnmanaged, size: u32) void {
    mem.writeIntLittle(u32, self.inner_list.items[0..@sizeOf(u32)], size);
}

/// Write a pickled value with a simple type to the internal memory buffer.
///
/// The list of supported types are...
/// - booleans,
/// - (un)signed integers,
/// - floats, and
/// - strings (`[]const u8`, `[]const u16`, and `[]const u32`).
///
/// Some important things to note...
///
/// - If you'd like to write `const` slices of `u8`, `u16`, or `u32`, you can
///   use `@constCast` to have them encoded in little-endian instead of treated
///   as strings.
/// - Recursive types (e.g. `[]const []const u8` or `[5][]const u16`) are
///   unsupported.
/// - While integers and floats larger than 64 bits are supported, they are not
///   recommended to be used unless you will be reading them with a program that
///   also supports them.
/// - Integers without a factor of 8 will still be serialized as if they do.
///
/// This method will `@panic` if the `len` field of `.inner_list.items` cannot
/// fit a `u32` (assumes outside 'foul-play').
pub fn write(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    value: T,
) Allocator.Error!usize {
    comptime switch (@typeInfo(T)) {
        .Bool, .Int, .Float => {},
        .Array => |arr| switch (@typeInfo(arr.child)) {
            .Bool, .Int, .Float => {},
            else => @compileError("Cannot write recursive type '" ++ @typeName(T) ++ "'"),
        },
        .Pointer => |ptr| switch (ptr.size) {
            .Many => @compileError("Use .writeMany or .writeManySentinel for many-item pointers"),
            .Slice => switch (@typeInfo(ptr.child)) {
                .Bool, .Int, .Float => {},
                else => @compileError("Cannot write recursive type '" ++ @typeName(T) ++ "'"),
            },
            else => @compileError("Cannot write recursive type '" ++ @typeName(T) ++ "'"),
        },
        else => if (@sizeOf(T) > 0) @compileError("Cannot write type '" ++ @typeName(T) ++ "'"),
    };

    if (@sizeOf(T) == 0) return 0 else if (self.inner_list.items.len < @sizeOf(u32))
        @panic("Unable to write header_size to pickled memory");

    var header_size: usize = @intCast(self.getHeaderSize());
    defer self.setHeaderSize(@truncate(header_size));

    var bytes_written = try self.innerWrite(allocator, T, value);
    header_size += bytes_written;

    return bytes_written;
}

/// Write a pickled many-item pointer to the internal memory buffer.
///
/// See the documentation for `.write` on which types may be pickled.
pub fn writeMany(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    ptr: [*]const T,
    len: usize,
) Allocator.Error!usize {
    comptime switch (@typeInfo(T)) {
        .Bool, .Int, .Float => {},
        .Array, .Pointer => @compileError("Cannot write recursive type '" ++ @typeName(T) ++ "'"),
        else => if (@sizeOf(T) > 0) @compileError("Cannot write type '" ++ @typeName(T) ++ "'"),
    };

    if (@sizeOf(T) == 0) return 0 else if (self.inner_list.items.len < @sizeOf(u32))
        @panic("Unable to write header_size to pickled memory");

    var bytes_written: usize = @intCast(self.getHeaderSize());
    defer self.setHeaderSize(@truncate(bytes_written));

    bytes_written += try self.innerWriteMany(allocator, T, ptr, len);
    return bytes_written;
}

/// Write a pickled many-item pointer (with a sentinel) to the internal memory
/// buffer.
///
/// See the documentation for `.write` on which types may be pickled.
pub inline fn writeManySentinel(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    comptime sentinel: T,
    ptr: [*:sentinel]const T,
    len: usize,
) Allocator.Error!usize {
    return self.writeMany(allocator, T, ptr, len + 1);
}

/// An internal writing method used for pickling the value of simple types
/// without worrying about managing the `header_size` or valid types, which are
/// left to `.write`.
fn innerWrite(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    value: T,
) Allocator.Error!usize {
    switch (@typeInfo(T)) {
        .Bool => {
            var target_mem = try self.inner_list.addOne(allocator);
            mem.writeIntLittle(u1, target_mem, @intFromBool(value));

            return @sizeOf(u1);
        },
        .Int => {
            var target_mem = try self.inner_list.addManyAsArray(allocator, @sizeOf(T));
            mem.writeIntLittle(T, target_mem, value);

            return @sizeOf(T);
        },
        .Float => {
            const Int = meta.Int(.unsigned, @as(u16, @sizeOf(T) * 8));
            const int = @as(*const Int, @ptrCast(&value)).*;

            var target_mem = try self.inner_list.addManyAsArray(allocator, @sizeOf(T));
            mem.writeIntLittle(Int, target_mem, int);

            return @sizeOf(Int);
        },
        .Array => |arr| {
            const sentinel = meta.sentinel(T);
            const len_size = try self.innerWrite(
                allocator,
                u31,
                @as(u31, @truncate(value.len)),
            );

            return len_size + if (sentinel == null)
                self.writeMany(allocator, arr.child, &value, arr.len)
            else
                self.writeManySentinel(allocator, arr.child, sentinel, &value, arr.len);
        },
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => {
                const sentinel = comptime meta.sentinel(T);

                if (ptr.is_const) switch (ptr.child) {
                    u8, u16, u32 => return copy_str: {
                        const len_size = try self.innerWrite(
                            allocator,
                            u31,
                            @as(u31, @truncate(value.len)),
                        );
                        const len_bytes = value.len * @sizeOf(ptr.child) + @as(
                            usize,
                            if (sentinel == null) 0 else 1,
                        );

                        var slice = try self.inner_list.addManyAsSlice(allocator, len_bytes);
                        @memcpy(slice, @as([*]const u8, @ptrCast(value.ptr)));

                        break :copy_str len_size + len_bytes;
                    },
                    else => {},
                };

                return self.innerWriteMany(
                    allocator,
                    ptr.child,
                    value.ptr,
                    value.len + if (sentinel == null) 0 else 1,
                );
            },
            else => unreachable,
        },
        else => unreachable,
    }
}

/// An internal writing method used for pickling the value of simple types
/// referenced by a many-item pointer and pointer arithmetic on said pointer,
/// without worrying about managing the `header_size` or valid types, which are
/// left to `.writeMany`.
fn innerWriteMany(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    ptr: [*]const T,
    len: usize,
) Allocator.Error!usize {
    var written_bytes = try self.innerWrite(allocator, u31, @as(u31, @truncate(len)));

    var i: usize = 0;
    while (i < len) : (i += 1) written_bytes += try self.innerWrite(allocator, T, ptr[i]);

    return written_bytes;
}

test "gherkin.GherkinUnmanaged/GherkinUnmanaged.toManaged" {
    var unmanaged_gherkin = try init(testing.allocator, .{});

    _ = try unmanaged_gherkin.write(testing.allocator, []const u8, "foobar");

    var copy = try testing.allocator.dupe(u8, unmanaged_gherkin.inner_list.items);
    defer testing.allocator.free(copy);

    var gherkin = unmanaged_gherkin.toManaged(testing.allocator);
    defer gherkin.deinit();

    try testing.expectEqualStrings(copy, gherkin.unmanaged.inner_list.items);
}
