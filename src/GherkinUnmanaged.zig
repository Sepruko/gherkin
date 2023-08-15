//! A Gherkin, but the allocator is passed as a parameter to any method calls
//! that require it.
//!
//! The same allocator **must** be used throughout the lifetime of a
//! GherkinUnmanaged.

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Gherkin = @import("Gherkin.zig");

/// The internal `std.ArrayListUnmanaged`. Used for dynamically scaling the
/// allocated memory required.
inner_list: InnerList,

/// Internal reference to the container.
const GherkinUnmanaged = @This();

/// This type exists due to changes with the type system in Zig 0.11.0, it also
/// provides an easy reference to the exact type used by GherkinUnmanaged.
pub const InnerList = ArrayListUnmanaged(u8);

/// Options for when initializing a new GherkinUnmanaged with `init`.
pub const Options = struct {
    header_size: u32 = @sizeOf(u32),
};

/// Initialize a new GherkinUnmanaged. Used for writing simple values as binary
/// data to memory.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn init(allocator: Allocator, options: Options) Allocator.Error!GherkinUnmanaged {
    if (options.header_size < @sizeOf(u32))
        @panic(fmt.comptimePrint("Provided options.header_size is <{d}", .{@sizeOf(u32)}));

    var list = try InnerList.initCapacity(allocator, options.header_size);

    var header_size_bytes = list.addManyAsArrayAssumeCapacity(@sizeOf(u32));
    mem.writeIntLittle(u32, header_size_bytes, options.header_size);

    return .{
        .inner_list = list,
    };
}

/// Deinitialize a GherkinUnmanaged, cleaning up any memory still allocated with
/// the passed `allocator`.
pub fn deinit(self: *GherkinUnmanaged, allocator: Allocator) void {
    self.inner_list.deinit(allocator);
    self.* = undefined;
}

/// Convert this GherkinUnmanaged into the memory-managed equivalent. The
/// returned gherkin has ownership of the allocated memory.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn toManaged(self: *GherkinUnmanaged, allocator: Allocator) Gherkin {
    return .{
        .unmanaged = self.*,
        .allocator = allocator,
    };
}

/// Create a new GherkinUnmanaged with ownership of the passed slice. The same
/// `allocator` that was used to allocate the passed memory must be used
/// throughout the lifetime of the returned gherkin.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn fromOwnedSlice(slice: []u8) GherkinUnmanaged {
    return .{
        .inner_list = InnerList.fromOwnedSlice(slice),
    };
}

/// Create a new GherkinUnmanaged with ownership of the passed slice. The same
/// allocator that was used to allocate the passed memory must be used
/// throughout the lifetime of the returned gherkin.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn fromOwnedSliceSentinel(comptime sentinel: u8, slice: [:sentinel]u8) GherkinUnmanaged {
    return .{
        .inner_list = InnerList.fromOwnedSliceSentinel(sentinel, slice),
    };
}

/// The caller owns the returned memory, emptying this gherkin. The `deinit`
/// method remains safe to call, however, it is unnecessary.
pub fn toOwnedSlice(self: *GherkinUnmanaged, allocator: Allocator) Allocator.Error![]u8 {
    var owned_slice = try self.inner_list.toOwnedSlice(allocator);
    errdefer allocator.free(owned_slice);

    self.* = try init(allocator, .{});
    return owned_slice;
}

/// The caller owns the returned memory, emptying this gherkin. The `deinit`
/// method remains safe to call, however, it is unnecessary.
pub inline fn toOwnedSliceSentinel(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime sentinel: u8,
) Allocator.Error![]u8 {
    return self.toOwnedSlice(allocator)[0.. :sentinel];
}

/// Create a copy of the GherkinUnmanaged. The same `allocator` must be used
/// throughout the lifetime of the returned gherkin.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn clone(self: GherkinUnmanaged, allocator: Allocator) Allocator.Error!GherkinUnmanaged {
    return .{
        .inner_list = try self.inner_list.clone(allocator),
    };
}

/// An internal method for readably retrieving the `header_size` of the gherkin.
inline fn getHeaderSize(self: GherkinUnmanaged) u32 {
    return mem.readIntLittle(u32, self.inner_list.items[0..4]);
}

/// An internal method for readably setting the `header_size` of the gherkin.
inline fn setHeaderSize(self: *GherkinUnmanaged, size: u32) void {
    mem.writeIntLittle(u32, self.inner_list.items[0..4], size);
}

/// Write a simple type as binary data to memory. The same `allocator` must be
/// used throughout the lifetime of the gherkin.
///
/// The supported types are...
///
/// - integers (`u8`, `u67`, `i16`, etc.)
/// - booleans (`true` and `false`)
/// - arrays (as long as their child type is also supported)
/// - pointers (single-item pointers and slices are supported, as long as their child type is also supported)
///
/// The special cases are...
///
/// - `[]u8` slices are appended as-is (treated as 'raw' data)
/// - `[(:sentinel)](const )integer` slices (not `[]u8`) are copied directly
///
/// For writing many-item pointers, use `writeMany` or `writeManySentinel`.
pub inline fn write(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    value: T,
) Allocator.Error!usize {
    var written_bytes = try self.innerWrite(allocator, T, value);
    self.setHeaderSize(self.getHeaderSize() + @as(u32, @truncate(written_bytes)));

    return written_bytes;
}

/// Used to write many-item pointers to memory as binary data. See the
/// documentation for `write` to see what child types are supported.
pub fn writeMany(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    ptr: [*]const T,
    len: usize,
) Allocator.Error!usize {
    var written_bytes: usize = @sizeOf(i32);

    // Re-validated in the following defer block.
    var target_memory = try self.inner_list.addManyAsArray(allocator, @sizeOf(i32));
    const size_index = self.inner_list.items.len - @sizeOf(i32);
    defer {
        target_memory = @ptrCast(self.inner_list.items[size_index .. size_index + @sizeOf(u32)].ptr);
        mem.writeIntLittle(u31, target_memory, @as(u31, @truncate(written_bytes)));
    }

    var i: usize = 0;
    while (i < len) : (i += 1) written_bytes += try self.write(allocator, T, ptr[i]);

    return written_bytes;
}

/// Used to write many-item pointers to memory as binary data. See the
/// documentation for `write` to see what child types are supported.
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

/// The internal write method, which may call itself. This is used to ensure the
/// `usize` returned from `write` is correct, and to separate the `header_size`
/// updating logic from the meat.
fn innerWrite(
    self: *GherkinUnmanaged,
    allocator: Allocator,
    comptime T: type,
    value: T,
) Allocator.Error!usize {
    return switch (@typeInfo(T)) {
        .Bool => self.innerWrite(allocator, u1, @intFromBool(value)),
        .Int => write_int: {
            var target_memory = try self.inner_list.addManyAsArray(allocator, @sizeOf(T));
            mem.writeIntLittle(T, target_memory, value);

            break :write_int @sizeOf(T);
        },
        .Array => |array_info| return if (array_info.sentinel == null)
            self.writeMany(allocator, array_info.child, &value, array_info.size)
        else
            self.writeManySentinel(allocator, array_info.child, &value, array_info.size),
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => self.innerWrite(allocator, ptr_info.child, value.*),
            .Many => @compileError("Please use .writeMany or .writeManySentinel for many-item pointers"),
            .Slice => if (T == []u8) blk: {
                try self.inner_list.appendSlice(allocator, value);
                break :blk value.len;
            } else if (@typeInfo(ptr_info.child) == .Int) blk: {
                const len = @sizeOf(ptr_info.child) * value.len;

                _ = try self.innerWrite(allocator, u31, @as(u31, @truncate(len)));
                var target_memory = try self.inner_list.addManyAsSlice(allocator, len);
                @memcpy(target_memory, @as([*]const u8, @ptrCast(value.ptr)));

                break :blk @sizeOf(i32) + len;
            } else if (ptr_info.sentinel == null)
                self.writeMany(allocator, ptr_info.child, value.ptr, value.len)
            else
                self.writeManySentinel(allocator, ptr_info.child, value.ptr, value.len),
            else => @compileError(
                "Cannot write pointer with size '" ++ @tagName(ptr_info.size) ++ "'",
            ),
        },
        else => @compileError("Cannot write type '" ++ @typeName(T) ++ "'"),
    };
}
