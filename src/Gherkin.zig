//! Allows for writing particular simple data types as binary data to an
//! in-memory slice, which can then be retrieved for writing to an
//! `std.io.Writer`.
//!
//! This struct internally stores an `std.mem.Allocator` for memory management.
//! To manually specify an allocator with each method call see
//! `GherkinUnmanaged`.

const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const Allocator = mem.Allocator;
const GherkinUnmanaged = @import("GherkinUnmanaged.zig");

/// The unmanaged gherkin that is wrapped by this memory-managed alternative.
unmanaged: GherkinUnmanaged,

/// The allocator used to perform automatic memory management, passed to
/// appropriate methods called on the value held in `unmanaged`.
allocator: Allocator,

/// Internal reference to the container.
const Gherkin = @This();

/// This type exists due to changes with the type system in Zig 0.11.0, it also
/// provides an easy reference to the exact type used by the wrapped
/// GherkinUnmanaged.
pub const InnerList = GherkinUnmanaged.InnerList;

/// Options for when initializing a new Gherkin with `init`, this is merged with
/// GherkinUnmanaged's type of the same name.
pub const Options = @Type(.{ .Struct = .{
    .layout = .Auto,
    .fields = meta.fields(struct {
        unmanaged: ?GherkinUnmanaged = null,
    }) ++ meta.fields(GherkinUnmanaged.Options),
    .decls = &[_]std.builtin.Type.Declaration{},
    .is_tuple = false,
} });

/// Initialize a new Gherkin. Used for writing simple values as binary
/// data to memory.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
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

/// Deinitialize a GherkinUnmanaged, cleaning up any memory still allocated with
/// the internal `allocator`.
pub fn deinit(self: *Gherkin) void {
    self.unmanaged.deinit(self.allocator);
    self.* = undefined;
}

/// Convert this Gherkin into the memory-unmanaged equivalent. The returned
/// gherkin has ownership of the allocated memory.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn moveToUnmanaged(self: *Gherkin) Allocator.Error!GherkinUnmanaged {
    const unmanaged = self.unmanaged;
    self.* = try init(self.allocator, .{});

    return unmanaged;
}

/// Create a new Gherkin with ownership of the passed slice.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn fromOwnedSlice(allocator: Allocator, slice: []u8) Gherkin {
    return .{
        .unmanaged = GherkinUnmanaged.fromOwnedSlice(slice),
        .allocator = allocator,
    };
}

/// Create a new Gherkin with ownership of the passed slice.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
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

/// The caller owns the returned memory, emptying this gherkin. The `deinit`
/// method remains safe to call, however, it is unnecessary.
pub inline fn toOwnedSlice(self: *Gherkin) Allocator.Error![]u8 {
    return self.unmanaged.toOwnedSlice(self.allocator);
}

/// The caller owns the returned memory, emptying this gherkin. The `deinit`
/// method remains safe to call, however, it is unnecessary.
pub inline fn toOwnedSliceSentinel(
    self: *GherkinUnmanaged,
    comptime sentinel: u8,
) Allocator.Error![]u8 {
    return self.toOwnedSlice(self.allocator)[0.. :sentinel];
}

/// Create a copy of the Gherkin.
///
/// Deinitialize with `deinit`, `toOwnedSlice`, or `toOwnedSliceSentinel`.
pub fn clone(self: Gherkin) Allocator.Error!Gherkin {
    return .{
        .unmanaged = try self.unmanaged.clone(self.allocator),
        .allocator = self.allocator,
    };
}

/// Write a simple type as binary data to memory. The same `allocator` must be
/// used throughout the lifetime of the gherkin.
///
/// See the documentation for `GherkinUnmanaged.write` for more details about
/// supported value types and special cases.
pub inline fn write(self: *Gherkin, comptime T: type, value: T) Allocator.Error!usize {
    return self.unmanaged.write(self.allocator, T, value);
}

/// Used to write many-item pointers to memory as binary data. See the
/// documentation for `GherkinUnmanaged.write` to see what child types are
/// supported.
pub inline fn writeMany(
    self: *Gherkin,
    comptime T: type,
    ptr: [*]const T,
    len: usize,
) Allocator.Error!usize {
    return self.unmanaged.writeMany(self.allocator, T, ptr, len);
}

/// Used to write many-item pointers to memory as binary data. See the
/// documentation for `GherkinUnmanaged.write` to see what child types are
/// supported.
pub inline fn writeManySentinel(
    self: *Gherkin,
    comptime T: type,
    comptime sentinel: T,
    ptr: [*:sentinel]const T,
    len: usize,
) Allocator.Error!usize {
    return self.writeMany(T, ptr, len + 1);
}
