const std = @import("std");
const meta = std.meta;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Type = std.builtin.Type;

pub const Gherkin = struct {
    unmanaged: GherkinUnmanaged,
    allocator: Allocator,

    pub const Options = @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = meta.fields(struct {
                unmanaged: ?GherkinUnmanaged = null,
            }) ++ meta.fields(GherkinUnmanaged.Options),
            .decls = &[_]Type.Declaration{},
            .is_tuple = false,
        },
    });

    pub fn init(allocator: Allocator, options: Options) !Gherkin {
        return .{
            .unmanaged = options.unmanaged orelse try GherkinUnmanaged.init(
                allocator,
                get_unmanaged_options: {
                    const ptr: *GherkinUnmanaged.Options = @ptrFromInt(
                        @intFromPtr(&options) + @offsetOf(
                            Options,
                            meta.fields(GherkinUnmanaged.Options)[0].name,
                        ),
                    );

                    break :get_unmanaged_options ptr.*;
                },
            ),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Gherkin) void {
        self.unmanaged.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn fromOwnedSlice(allocator: Allocator, slice: []u8) Gherkin {
        return .{
            .unmanaged = GherkinUnmanaged.fromOwnedSlice(slice),
            .allocator = allocator,
        };
    }

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

    pub fn moveToUnmanaged(self: *Gherkin) !GherkinUnmanaged {
        const allocator = self.allocator;
        var unmanaged = self.unmanaged;
        self.* = try init(allocator, .{});
        return unmanaged;
    }

    pub fn toOwnedSlice(self: *Gherkin) ![]u8 {
        const allocator = self.allocator;

        var owned_slice = try self.unmanaged.inner_list.toOwnedSlice(allocator);
        errdefer allocator.free(owned_slice);

        self.* = try init(allocator, .{});
        return owned_slice;
    }

    pub fn toOwnedSliceSentinel(self: *Gherkin, comptime sentinel: u8) ![:sentinel]u8 {
        const allocator = self.allocator;

        var owned_slice = try self.unmanaged.inner_list.toOwnedSliceSentinel(allocator, sentinel);
        errdefer allocator.free(owned_slice);

        self.* = try init(allocator, .{});
        return owned_slice;
    }
};

pub const GherkinUnmanaged = struct {
    inner_list: InnerList,

    const InnerList = std.ArrayListUnmanaged(u8);

    pub const Options = struct {
        header_size: usize = @sizeOf(u32),
    };

    pub fn init(allocator: Allocator, options: Options) !GherkinUnmanaged {
        if (options.header_size < @sizeOf(u32))
            @panic("options.header_size too small, must be bigger than @sizeOf(u32)");

        return .{
            .inner_list = try InnerList.initCapacity(allocator, options.header_size),
        };
    }

    pub fn deinit(self: *GherkinUnmanaged, allocator: Allocator) void {
        self.inner_list.deinit(allocator);
        self.* = undefined;
    }

    pub fn fromOwnedSlice(slice: []u8) GherkinUnmanaged {
        if (slice.len < @sizeOf(u32))
            @panic("slice is too small to possibly fit an LE u32 header length");

        return .{
            .inner_list = InnerList.fromOwnedSlice(slice),
        };
    }

    pub fn fromOwnedSliceSentinel(comptime sentinel: u8, slice: [:sentinel]u8) ![:sentinel]u8 {
        if (slice.len < @sizeOf(u32))
            @panic("slice is too small to possibly fit an LE u32 header length");

        return .{
            .inner_list = InnerList.fromOwnedSliceSentinel(sentinel, slice),
        };
    }

    pub fn toManaged(self: *GherkinUnmanaged, allocator: Allocator) Gherkin {
        return .{
            .unmanaged = self.*,
            .allocator = allocator,
        };
    }

    pub fn toOwnedSlice(self: *GherkinUnmanaged, allocator: Allocator) ![]u8 {
        var owned_slice = try self.inner_list.toOwnedSlice(allocator);
        errdefer allocator.free(owned_slice);

        self.* = try init(allocator, .{});
        return owned_slice;
    }

    pub fn toOwnedSliceSentinel(
        self: *GherkinUnmanaged,
        allocator: Allocator,
        comptime sentinel: u8,
    ) ![:sentinel]u8 {
        var owned_slice = try self.inner_list.toOwnedSliceSentinel(allocator, sentinel);
        errdefer allocator.free(owned_slice);

        self.* = try init(allocator, .{});
        return owned_slice;
    }
};

test Gherkin {
    var gherkin: *Gherkin = try testing.allocator.create(Gherkin);
    defer testing.allocator.destroy(gherkin);

    gherkin.* = try Gherkin.init(testing.allocator, .{});
    defer gherkin.deinit();
}

test GherkinUnmanaged {
    var unmanaged_gherkin: *GherkinUnmanaged = try testing.allocator.create(GherkinUnmanaged);
    defer testing.allocator.destroy(unmanaged_gherkin);

    unmanaged_gherkin.* = try GherkinUnmanaged.init(testing.allocator, .{});
    defer unmanaged_gherkin.deinit(testing.allocator);
}
