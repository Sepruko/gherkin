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
