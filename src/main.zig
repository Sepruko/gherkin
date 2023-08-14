const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Gherkin = struct {
    unmanaged: GherkinUnmanaged,
    allocator: Allocator,

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
        if (options.header_size < @sizeOf(u32))
            @panic(fmt.comptimePrint("Provided options.header_size is <{d}", .{@sizeOf(u32)}));

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

    pub fn moveToUnmanaged(self: *Gherkin) GherkinUnmanaged {
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
};

const GherkinUnmanaged = struct {
    inner_list: InnerList,

    pub const InnerList = ArrayListUnmanaged(u8);

    pub const Options = struct {
        header_size: u32 = @sizeOf(u32),
    };

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

    pub fn deinit(self: *GherkinUnmanaged, allocator: Allocator) void {
        self.inner_list.deinit(allocator);
        self.* = undefined;
    }

    pub fn toManaged(self: *GherkinUnmanaged, allocator: Allocator) Gherkin {
        return .{
            .unmanaged = self.*,
            .allocator = allocator,
        };
    }

    pub fn fromOwnedSlice(slice: []u8) GherkinUnmanaged {
        return .{
            .inner_list = InnerList.fromOwnedSlice(slice),
        };
    }

    pub fn fromOwnedSliceSentinel(comptime sentinel: u8, slice: [:sentinel]u8) GherkinUnmanaged {
        return .{
            .inner_list = InnerList.fromOwnedSliceSentinel(sentinel, slice),
        };
    }

    pub fn toOwnedSlice(self: *GherkinUnmanaged, allocator: Allocator) Allocator.Error![]u8 {
        var owned_slice = try self.inner_list.toOwnedSlice(allocator);
        errdefer allocator.free(owned_slice);

        self.* = try init(allocator, .{});
        return owned_slice;
    }

    pub inline fn toOwnedSliceSentinel(
        self: *GherkinUnmanaged,
        allocator: Allocator,
        comptime sentinel: u8,
    ) Allocator.Error![]u8 {
        return self.toOwnedSlice(allocator)[0.. :sentinel];
    }

    pub fn clone(self: GherkinUnmanaged, allocator: Allocator) Allocator.Error!GherkinUnmanaged {
        return .{
            .inner_list = try self.inner_list.clone(allocator),
        };
    }

    inline fn getHeaderSize(self: GherkinUnmanaged) u32 {
        return mem.readIntLittle(u32, self.inner_list.items[0..4]);
    }

    inline fn setHeaderSize(self: *GherkinUnmanaged, size: u32) void {
        mem.writeIntLittle(u32, self.inner_list.items[0..4], size);
    }

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
                .Slice => if (ptr_info.sentinel == null)
                    if (T == []u8) append_raw: {
                        try self.inner_list.appendSlice(allocator, value);
                        break :append_raw value.len;
                    } else if (@typeInfo(ptr_info.child) == .Int) append_as_u8_slice: {
                        const len = @sizeOf(ptr_info.child) * value.len;

                        _ = try self.innerWrite(allocator, u31, @as(u31, @truncate(len)));
                        var target_memory = try self.inner_list.addManyAsSlice(allocator, len);
                        @memcpy(target_memory, @as([*]const u8, @ptrCast(value.ptr)));

                        break :append_as_u8_slice @sizeOf(i32) + len;
                    } else self.writeMany(allocator, ptr_info.child, value.ptr, value.len)
                else
                    self.writeManySentinel(allocator, ptr_info.child, value.ptr, value.len),
                else => @compileError(
                    "Cannot write pointer with size '" ++ @tagName(ptr_info.size) ++ "'",
                ),
            },
            else => @compileError("Cannot write type '" ++ @typeName(T) ++ "'"),
        };
    }
};
