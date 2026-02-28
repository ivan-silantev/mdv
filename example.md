# mdv CommonMark renderer showcase

This file is a compact manual test for the Zig-only `mdv` renderer. It includes the most important block and inline constructs that the current implementation should display in the terminal and export with `--html`.

## Inline formatting

Plain text can include *emphasis*, _underscore emphasis_, **strong emphasis**, and __underscore strong emphasis__.

Escaped punctuation should stay literal: \*not emphasized\*, \[not a link](/ignored), and \`not code\`.

Code spans support simple and nested backticks: `std.debug.print("hi", .{});` and `` code with ` inside ``.

Entities and autolinks: &amp; &lt; &gt; &quot; &apos; &nbsp; <https://spec.commonmark.org/0.31.2/> <hello@example.com>.

Links and images: [CommonMark spec](https://spec.commonmark.org/0.31.2/) and ![sample image](assets/sample.png).

Hard line break with two trailing spaces.  
This line should start after a hard break.

Hard line break with a trailing backslash.\
This line should also start after a hard break.

## ATX headings

### Heading level 3 ###

#### Heading level 4

###### Heading level 6

Setext heading level 1
======================

Setext heading level 2
----------------------

## Thematic breaks

---

* * *

___

## Block quotes

> A simple quote with **strong text** and `inline code`.
> A second quoted line.
>
> [A quoted link](https://example.com)

## Lists

- Dash bullet
* Star bullet
+ Plus bullet

1. Ordered item one
2. Ordered item two
3) Ordered item with a closing parenthesis marker

Nested list smoke test:

- Parent item
  - Child item rendered with preserved indentation
  1. Child ordered item rendered with preserved indentation

Loose-list smoke test:

- First loose item

- Second loose item

## Indented code block

    const std = @import("std");
    pub fn main() !void {
        std.debug.print("indented code\\n", .{});
    }

## Fenced code blocks

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("fenced backtick code\\n", .{});
}
```

~~~markdown
# Markdown inside a tilde fence

- This should stay literal.
~~~

## Raw HTML

<div class="note">
Raw HTML block smoke test.
</div>

Inline raw HTML smoke test: <span class="badge">badge</span>.

## Link reference definitions

The current renderer omits simple reference definitions from output, but full reference-link resolution is still pending.

[commonmark-reference]: https://spec.commonmark.org/0.31.2/ "CommonMark 0.31.2"

## Known partial areas

- Nested containers are not fully CommonMark-compliant yet.
- Tight vs loose list semantics are not fully modeled yet.
- Reference links such as [CommonMark][commonmark-reference] are not resolved yet.
- Emphasis still uses a simplified parser instead of the CommonMark delimiter stack.
