# 🥒 `gherkin`

A re-implementation of [`pickle.h`][pickle.h] in the
[Zig programming language][zig].

> **Warning**
> This library targets the [`0.11.0` release][zig-target-release] of Zig. It
> will **not** work on prior releases, and may not work on future releases.

## Documentation

You can find in-code documentation in all source files under the [`./src`](src)
directory. It's recommended to use a language server (e.g. [ZLS][gh-zls]) that
supports hover and goto-definitions in your IDE of choice.

## Usage

### Importing the `gherkin` Library

#### Zig

Including this library in your `build.zig.zon` dependencies is easy!

```zon
.{
    .name = "my-project-name",
    .version = "1.0.0",

    .dependencies = .{
        .gherkin = .{
            .url = "https://github.com/Sepruko/gherkin/archive/refs/tags/v0.1.1.tar.gz",
            .hash = "<computed hash>",
        },
    },
}
```

#### C & C-Interoperable Languages

> **Warning**
> No support for these languages currently exists.

### Creating a `Gherkin` or `GherkinUnmanaged`

You can use either the `Gherkin` or `GherkinUnmanaged` structs to write simple
values to memory as binary data, following the format output by
[`pickle.h`][pickle.h].

> **Warning**
> This section **DOES NOT** apply to C or C-Interoperable languages, only Zig.

```zig
const std = @import("std");
const heap = std.heap;
const GeneralPurposeAllocator = heap.GeneralPurposeAllocator;

const gherkin = @import("gherkin");
const Gherkin = gherkin.Gherkin;

var gpa = GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var my_gherkin = try Gherkin.init(allocator, .{});
    defer my_gherkin.deinit();

    // Your gherkin is now ready for writing! See the documentation for `.write`
    // to see which types you can write, as well as any special cases.

    _ = try my_gherkin.write([]const u8, "foo");
    _ = try my_gherkin.write(f32, 0.43);
    _ = try my_gherkin.write([]u8, @constCast(&[_]u8{0, 1, 2, 3, 4}));

    // ...
}
```

### Reading a from a `Gherkin` or `GherkinUnmanaged`

You can create an `Iterator` directly from a `Gherkin` or `GherkinUnmanaged`
via the `iterator` method, *or* from the `Iterator.init` function. You can then
use this iterator to read simple value types from a pickled buffer.

> **Warning**
> This section **DOES NOT** apply to C or C-Interoperable languages, only Zig.

```zig
const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const GeneralPurposeAllocator = heap.GeneralPurposeAllocator;

const gherkin = @import("gherkin");
const Gherkin = gherkin.Gherkin;

var gpa = GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var my_gherkin = try Gherkin.init(allocator, .{});
    defer my_gherkin.deinit();

    _ = try my_gherkin.write([]const u8, "foo");

    var my_iterator = my_gherkin.iterator();
    // This isn't required, but may help with debugging.
    defer my_iterator.deinit();

    // Your iterator is ready for reading! See the documentation for
    // `gherkin.GherkinUnmanaged.write` to see which types may be read, as well
    // as `.next` for any special cases.

    const foo_str = try my_iterator.nextAlloc(allocator, []const u8);
    defer allocator.free(foo_str);

    debug.print(foo_str); // foo
}
```

## Contributing

Soon™

---

*Thanks, and have fun! — Gabe Logan Newell*

[gh-zls]: https://github.com/zigtools/zls
[pickle.h]: https://chromium.googlesource.com/chromium/src/+/main/base/pickle.h
[zig]: https://ziglang.org/
[zig-target-release]: https://github.com/ziglang/zig/releases/0.11.0
