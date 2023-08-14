# 🥒 `gherkin`

A re-imagining of [`pickle.h`][pickle.h] in the
[Zig programming language][zig].

## Documentation

There is in-code documentation, which can be displayed with references and
call-sites when using a language server that supports definitions (such as ZLS).

## Using the Library

Below is an example of how to use the `Gherkin` export.

> **Note**
> You can also use the `GherkinUnmanaged` export, which will behave similarly to
> Zig's `std.ArrayListUnmanaged`.

```zig
const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const Allocator = mem.Allocator;
const Gherkin = @import("gherkin").Gherkin;

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var gherkin = try Gherkin.init(allocator, .{});
    defer gherkin.deinit();

    _ = try gherkin.write([]const u8, "Hello, World!");
    var gherkin_slice = try gherkin.toOwnedSlice();
    defer allocator.free(gherkin_slice);

    // 21, 13 - Hello, World!
    std.debug.print("{d}, {d} - {s}", .{
        mem.readIntLittle(u32, gherkin_slice[0..4]),
        mem.readIntLittle(i32, gherkin_slice[4..8]),
        gherkin_slice[8..],
    });
}
```

> **Warning**
> There is no support for the C ABI yet, meaning you cannot use this directory
> from C or any compatible languages.

## Contributing

Soon™

---

*Thanks, and have fun! — Gabe Logan Newell*

[pickle.h]: https://chromium.googlesource.com/chromium/src/+/main/base/pickle.h
[zig]: https://ziglang.org/
