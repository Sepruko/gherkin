//! Used for iterating over a `[]u8` buffer and attempting to read pickled
//! values from it.
//!
//! See the documentation for `gherkin.GherkinUnmanaged.write` as to which types
//! may be read, as parity must be ensured.

const GherkinIterator = @This();

const std = @import("std");
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const Allocator = mem.Allocator;

const Gherkin = @import("Gherkin.zig");

/// The pointer to the buffer that will be read from.
ptr: [*]const u8,

/// The current index that the iterator will read from.
index: usize = @sizeOf(u32),

/// The length of `ptr`.
len: usize,

/// Errors that may occur whilst attempting to iterate over pickled memory.
pub const Error = error{
    CollectionTooLarge,
    CollectionTooSmall,
    OutOfMemory,
};

/// Initialize a new `Iterator`.
pub fn init(buffer: []const u8) GherkinIterator {
    return .{
        .ptr = buffer.ptr,
        .len = buffer.len,
    };
}

/// Skip ahead `n` bytes in the buffer. This method ensures that the index
/// will not exceed the length, otherwise an error will be returned.
pub fn skip(self: *GherkinIterator, n: usize) error{OutOfMemory}!void {
    if (self.index + n > self.len) return error.OutOfMemory;
    self.index += n;
}

/// Backtrack `n` bytes in the buffer. This method ensures that the index
/// will not overflow, otherwise an error will be returned.
pub fn backtrack(self: *GherkinIterator, n: usize) error{OutOfMemory}!void {
    if (@as(bool, @bitCast(@subWithOverflow(self.index, n)[1]))) return error.OutOfMemory;
    self.index -= n;
}

/// Attempt to read type `T` from the pickled memory.
///
/// Some things to note...
///
/// - You must use `.nextAlloc` to read arrays or slices.
/// - You must use `.nextMany` or `.nextManySentinel` to read into many-item
///   pointers.
pub fn next(
    self: *GherkinIterator,
    comptime T: type,
) Error!T {
    if (self.index >= self.len) return error.OutOfMemory;

    switch (@typeInfo(T)) {
        .Bool, .Int, .Float => {},
        .Array => @compileError("Please use .nextAlloc for reading array values"),
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => @compileError("Please use .nextAlloc for reading slice values"),
            .Many => @compileError(
                "Please use .nextMany or .nextManySentinel for reading into a many-item pointer",
            ),
            else => @compileError("Cannot read complex type '" ++ @typeName(T) ++ "'"),
        },
        else => @compileError("Cannot read type '" ++ @typeName(T) ++ "'"),
    }

    return @call(.always_tail, innerNext, .{ self, T });
}

/// Attempt to read and allocate type `T` from the pickled memory.
///
/// Some things to note...
///
/// - You must use `.nextMany` or `.nextManySentinel` to read into many-item
///   pointers.
/// - You may not read too-little or too-many elements into an array, consider
///   reading a slice, or into a many-item pointer with `.nextMany` or
///   `.nextManySentinel` if you do not know the size of the collection.
pub fn nextAlloc(
    self: *GherkinIterator,
    allocator: Allocator,
    comptime T: type,
) (Error || Allocator.Error)!switch (@typeInfo(T)) {
    .Pointer => T,
    else => *T,
} {
    if (self.index >= self.len) return error.OutOfMemory;

    switch (@typeInfo(T)) {
        .Bool, .Int, .Float => {},
        .Array => |arr| switch (@typeInfo(arr.child)) {
            .Bool, .Int, .Float => {
                const sentinel = comptime meta.sentinel(T);
                const array_len: usize = @intCast(try self.next(u31));
                if (array_len > arr.len)
                    return error.CollectionTooLarge
                else if (array_len < arr.len)
                    return error.CollectionTooSmall;

                self.index -= @sizeOf(u31);

                var array = try allocator.create(T);
                _ = try if (sentinel == null)
                    self.nextMany(arr.child, array, arr.len)
                else
                    self.nextManySentinel(arr.child, sentinel, array, arr.len);

                return array;
            },
            else => @compileError("Cannot read complex type '" ++ @typeName(T) ++ "'"),
        },
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => switch (@typeInfo(ptr.child)) {
                .Int => {
                    const sentinel = comptime meta.sentinel(T);
                    const slice_len: usize = @intCast(try self.next(u31));

                    if (ptr.is_const) switch (ptr.child) {
                        u8, u16, u32 => return copy_str: {
                            var slice = try allocator.alloc(
                                ptr.child,
                                slice_len / @sizeOf(ptr.child),
                            );
                            @memcpy(slice, @as(
                                [*]const ptr.child,
                                @ptrCast(&self.ptr[self.index]),
                            ));

                            self.skip(slice_len) catch unreachable;
                            break :copy_str if (ptr.size == .Slice) slice else slice.ptr;
                        },
                        else => {},
                    };

                    self.index -= @sizeOf(u31);

                    var slice = try allocator.alloc(
                        ptr.child,
                        slice_len + if (sentinel == null) 0 else 1,
                    );
                    _ = try if (sentinel == null)
                        self.nextMany(ptr.child, slice.ptr, slice.len)
                    else
                        self.nextManySentinel(ptr.child, sentinel, slice.ptr, slice.len);

                    return slice;
                },
                .Bool, .Float => {
                    const sentinel = comptime meta.sentinel(T);
                    const slice_len: usize = @intCast(try self.next(u31));

                    self.index -= @sizeOf(u31);

                    var slice = try allocator.alloc(
                        ptr.child,
                        slice_len + if (sentinel == null) 0 else 1,
                    );
                    _ = try if (sentinel == null)
                        self.nextMany(ptr.child, slice.ptr, slice.len)
                    else
                        self.nextManySentinel(ptr.child, sentinel, slice.ptr, slice.len);

                    return slice;
                },
                else => @compileError("Cannot read complex type '" ++ @typeName(T) ++ "'"),
            },
            else => @compileError("Cannot read complex type '" ++ @typeName(T) ++ "'"),
        },
        else => @compileError("Cannot read type '" ++ @typeName(T) ++ "'"),
    }

    var ptr = try allocator.create(T);
    errdefer allocator.destroy(ptr);

    ptr.* = try self.next(T);
    return ptr;
}

/// Attempt to read `len` instances of `T` into `ptr`, returning the number of
/// successfully read instances.
pub fn nextMany(
    self: *GherkinIterator,
    comptime T: type,
    ptr: [*]T,
    len: usize,
) Error!usize {
    if (self.index >= self.len) return error.OutOfMemory;

    switch (@typeInfo(T)) {
        .Bool, .Int, .Float => {},
        else => @compileError("Cannot read complex type '" ++ @typeName(T) ++ "'"),
    }

    const ptr_len: usize = @intCast(try self.next(u31));
    if (ptr_len > len) return error.CollectionTooLarge;

    var i: usize = 0;
    while (i < ptr_len) : (i += 1) ptr[i] = try self.innerNext(T);

    return i;
}

/// Attempt to read `len` instances (with a sentinel) of `T` into `ptr`,
/// returning the number of successfully read instances.
pub inline fn nextManySentinel(
    self: *GherkinIterator,
    comptime T: type,
    comptime sentinel: T,
    ptr: [*:sentinel]T,
    len: usize,
) Error!usize {
    return self.nextMany(T, ptr, len + 1);
}

/// An internal writing method used for de-pickling the value of simple types
/// without worrying about type validation, which is left to `next`.
pub fn innerNext(self: *GherkinIterator, comptime T: type) Error!T {
    switch (@typeInfo(T)) {
        .Bool => {
            const size_t = @sizeOf(T);
            try self.skip(size_t);

            return @as(bool, @bitCast(@as(u1, @truncate(mem.readIntLittle(
                u8,
                @as(*const [size_t]u8, @ptrCast(&self.ptr[self.index - size_t])),
            )))));
        },
        .Int => |int| {
            const size_t = @sizeOf(T);
            try self.skip(size_t);

            return if (int.bits % 8 == 0)
                mem.readIntLittle(
                    T,
                    @as(*const [size_t]u8, @ptrCast(&self.ptr[self.index - size_t])),
                )
            else aligned: {
                const Int = math.ByteAlignedInt(T);
                break :aligned @as(T, @truncate(mem.readIntLittle(
                    Int,
                    @as(*const [size_t]u8, @ptrCast(&self.ptr[self.index - size_t])),
                )));
            };
        },
        .Float => {
            const size_t = @sizeOf(T);
            try self.skip(size_t);

            // @bitSizeOf reports incorrectly for f80.
            const Int = meta.Int(.unsigned, @sizeOf(T) * 8);
            return @as(*align(1) const T, @ptrCast(&mem.readIntLittle(
                Int,
                @as(*const [size_t]u8, @ptrCast(&self.ptr[self.index - size_t])),
            ))).*;
        },
        else => unreachable,
    }
}

test "gherkin.GherkinIterator/GherkinIterator.next" {
    var gherkin = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write(f64, 12.34);
    _ = try gherkin.write(i16, 40);

    var iterator = gherkin.iterator();

    const float_64 = try iterator.next(f64);
    try testing.expectEqual(@as(f64, 12.34), float_64);

    const int_16 = try iterator.next(i16);
    try testing.expectEqual(@as(i16, 40), int_16);
}

test "gherkin.GherkinIterator/GherkinIterator.nextAlloc" {
    var gherkin = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write([]const u8, "foobar");
    _ = try gherkin.write([5]f80, [5]f80{ 1.0, 2.0, 3.0, 4.0, 5.0 });

    var iterator = gherkin.iterator();

    var str_foobar = try iterator.nextAlloc(testing.allocator, []const u8);
    defer testing.allocator.free(str_foobar);
    try testing.expectEqualStrings("foobar", str_foobar);

    var arr_f80 = try iterator.nextAlloc(testing.allocator, [5]f80);
    defer testing.allocator.destroy(arr_f80);
    try testing.expectEqual([5]f80{ 1.0, 2.0, 3.0, 4.0, 5.0 }, arr_f80.*);
}

test "gherkin.GherkinIterator/GherkinIterator.nextMany" {
    var gherkin = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write([5]u8, [5]u8{ 1, 2, 3, 4, 5 });

    var iterator = gherkin.iterator();

    var slice_u8 = try testing.allocator.alloc(u8, 5);
    defer testing.allocator.free(slice_u8);

    const u8s_read = try iterator.nextMany(u8, slice_u8.ptr, slice_u8.len);
    try testing.expectEqual(@as(usize, 5), u8s_read);
    try testing.expectEqualSlices(u8, &[5]u8{ 1, 2, 3, 4, 5 }, slice_u8);
}

test "gherkin.GherkinIterator/GherkinIterator.nextManySentinel" {
    var gherkin = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write([5:0]u8, [5:0]u8{ 1, 2, 3, 4, 5 });

    var iterator = gherkin.iterator();

    var slice_u8 = try testing.allocator.allocSentinel(u8, 5, 0);
    defer testing.allocator.free(slice_u8);

    const u8s_read = try iterator.nextManySentinel(u8, 0, slice_u8.ptr, slice_u8.len);
    try testing.expectEqual(@as(usize, 6), u8s_read);
    try testing.expectEqualSlices(u8, &[5:0]u8{ 1, 2, 3, 4, 5 }, slice_u8);
}

test "gherkin.GherkinIterator/GherkinIterator.skip" {
    var gherkin = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write([]const u8, "foobar");

    var iterator = gherkin.iterator();

    try iterator.skip(4);
    try testing.expectError(
        error.OutOfMemory,
        iterator.skip(6 + 1),
    );
}

test "gherkin.GherkinIterator/GherkinIterator.backtrack" {
    var gherkin = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write([]const u8, "foobar");

    var iterator = gherkin.iterator();

    try iterator.backtrack(4);
    try testing.expectError(
        error.OutOfMemory,
        iterator.backtrack(@sizeOf(u32) + @sizeOf(i32) + 6 + 1),
    );
}
