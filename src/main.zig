const std = @import("std");
const build_options = @import("build_options");
const lang_plugins = @import("lang_plugins.zig");

const default_exts = [_][]const u8{
    "c",       "cpp",        "h",     "hpp",  "cmake",    "mk",     "bzl",      "py",
    "ipynb",   "js",         "jsx",   "ts",   "svelte",   "css",    "htm",      "html",
    "htmx",    "xhtml",      "go",    "java", "hs",       "fut",    "sol",      "move",
    "mo",      "rs",         "zig",   "sh",   "nix",      "tf",     "lua",      "yml",
    "json",    "proto",      "gql",   "sql",  "agda",     "asm",    "s",        "brs",
    "cc",      "cxx",        "hh",    "hxx",  "cs",       "clj",    "cljs",     "cljc",
    "coffee",  "litcoffee",  "iced",  "cr",   "scss",     "sass",   "less",     "styl",
    "dart",    "ex",         "exs",   "erl",  "hrl",      "fs",     "fsi",      "fsx",
    "f",       "for",        "f90",   "f95",  "f03",      "f08",    "groovy",   "gradle",
    "hbs",     "handlebars", "hx",    "hy",   "jade",     "jl",     "kt",       "kts",
    "tex",     "ly",         "ls",    "mjs",  "mochi",    "monkey", "mustache", "nim",
    "nims",    "m",          "mm",    "ml",   "mli",      "pl",     "pm",       "php",
    "prql",    "pug",        "r",     "rkt",  "rpy",      "rb",     "scala",    "nut",
    "svg",     "swift",      "tsx",   "vb",   "xml",      "yaml",   "vhd",      "vhdl",
    "v",       "vh",         "sv",    "svh",  "lagda",    "bs",     "csx",      "liticed",
    "stylus",  "escript",    "xrl",   "yrl",  "fsscript", "gvy",    "gy",       "gsh",
    "lhs",     "cjs",        "ily",   "lyi",  "mll",      "mly",    "t",        "pod",
    "phtml",   "php3",       "php4",  "php5", "phps",     "pyi",    "pyw",      "rktd",
    "rktl",    "rpym",       "rpymc", "sc",   "bas",      "cls",    "frm",      "shtml",
    "app.src",
};

const FileCount = struct {
    path: []const u8,
    ext: []const u8,
    test_count: u64,
    comment_count: u64,
    blank_count: u64,
    code_count: u64,

    fn total(self: FileCount) u64 {
        return self.test_count + self.comment_count + self.blank_count + self.code_count;
    }
};

const Options = struct {
    add: std.ArrayList([]const u8) = .empty,
    exclude: std.ArrayList([]const u8) = .empty,
    only: std.ArrayList([]const u8) = .empty,
    descending: bool = false,
    summary: bool = false,
    split_tests: bool = true,
    show_comments: bool = true,
    show_blanks: bool = false,
    count_symbol_only: bool = false,
    version: bool = false,
    help: bool = false,
};

const CountOptions = lang_plugins.CountOptions;

const RenderOptions = struct {
    split_tests: bool = true,
    show_comments: bool = true,
    show_blanks: bool = false,
};

const ArgError = error{ MissingValue, UnknownOption };

fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !Options {
    var opts = Options{};
    var i: usize = 1; // skip program name
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            opts.help = true;
        } else if (std.mem.eql(u8, a, "-d") or std.mem.eql(u8, a, "--descending")) {
            opts.descending = true;
        } else if (std.mem.eql(u8, a, "-s") or std.mem.eql(u8, a, "--summary")) {
            opts.summary = true;
        } else if (takeToggleFlag(a, "--split-tests", "--no-split-tests")) |v| {
            opts.split_tests = v;
        } else if (takeToggleFlag(a, "--comments", "--no-comments")) |v| {
            opts.show_comments = v;
        } else if (takeToggleFlag(a, "--blanks", "--no-blanks")) |v| {
            opts.show_blanks = v;
        } else if (takeToggleFlag(a, "--count-symbols", "--no-count-symbols")) |v| {
            opts.count_symbol_only = v;
        } else if (std.mem.eql(u8, a, "-V") or std.mem.eql(u8, a, "--version")) {
            opts.version = true;
        } else if (try takeValueArg(argv, &i, a, "-a", "--add")) |v| {
            try opts.add.append(allocator, v);
        } else if (try takeValueArg(argv, &i, a, "-e", "--exclude")) |v| {
            try opts.exclude.append(allocator, v);
        } else if (try takeValueArg(argv, &i, a, "-o", "--only")) |v| {
            try opts.only.append(allocator, v);
        } else if (try takeShortFlagBundle(a, &opts)) {} else {
            std.debug.print("sloc: unknown option: {s}\n", .{a});
            return ArgError.UnknownOption;
        }
    }
    return opts;
}

fn takeValueArg(
    argv: []const []const u8,
    i: *usize,
    a: []const u8,
    short: []const u8,
    long: []const u8,
) !?[]const u8 {
    if (std.mem.eql(u8, a, short) or std.mem.eql(u8, a, long)) {
        if (i.* + 1 >= argv.len) return ArgError.MissingValue;
        i.* += 1;
        return argv[i.*];
    }
    // --long=value
    if (std.mem.startsWith(u8, a, long) and a.len > long.len and a[long.len] == '=') {
        return a[long.len + 1 ..];
    }
    // -sVALUE
    if (a.len > short.len and std.mem.startsWith(u8, a, short)) {
        return a[short.len..];
    }
    return null;
}

fn takeToggleFlag(a: []const u8, positive: []const u8, negative: []const u8) ?bool {
    if (std.mem.eql(u8, a, positive)) return true;
    if (std.mem.eql(u8, a, negative)) return false;
    return null;
}

fn applyShortFlag(flag: u8, opts: *Options) !void {
    switch (flag) {
        'h' => opts.help = true,
        'd' => opts.descending = true,
        's' => opts.summary = true,
        'V' => opts.version = true,
        'n' => opts.split_tests = false,
        'c' => opts.show_comments = false,
        'b' => opts.show_blanks = true,
        'p' => opts.count_symbol_only = true,
        else => return ArgError.UnknownOption,
    }
}

fn takeShortFlagBundle(a: []const u8, opts: *Options) !bool {
    if (a.len < 2 or a[0] != '-' or a[1] == '-') return false;
    if (a[1] == 'a' or a[1] == 'e' or a[1] == 'o') return false;

    for (a[1..]) |flag| try applyShortFlag(flag, opts);
    return true;
}

fn printHelp(w: *std.Io.Writer) !void {
    try w.print("sloc {s}\n\n", .{build_options.version});
    try w.writeAll(
        \\Usage: sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-n] [-c] [-b] [-p]
        \\            [--split-tests|--no-split-tests] [--comments|--no-comments]
        \\            [--blanks|--no-blanks] [--count-symbols|--no-count-symbols]
        \\            [-V] [-h]
        \\Count code, test, and comment lines by default. Blank lines and symbol-only
        \\lines are excluded unless enabled.
        \\
        \\Options:
        \\  -a, --add ext1,ext2     Include additional file extensions
        \\  -e, --exclude ext1,ext2 Exclude specified file extensions
        \\  -o, --only ext1,ext2    Include ONLY the specified extensions (overrides -a and -e)
        \\  -d, --descending        Display results in descending order by line count
        \\  -s, --summary           Summary mode - only show totals
        \\  -n, --no-split-tests    Merge test lines into the main code/lines column
        \\  -c, --no-comments       Exclude comment lines from counts and output
        \\  -b, --blanks            Show blank-line counts (default: off)
        \\  -p, --count-symbols     Count symbol-only lines as code/test (default: off)
        \\      --split-tests       Show separate code and test columns (default: on)
        \\      --comments          Show comment-line counts (default: on)
        \\      --no-blanks         Exclude blank lines from counts and output
        \\      --no-count-symbols  Exclude symbol-only lines from counts
        \\  -V, --version           Display version information
        \\  -h, --help              Display this help message
        \\                          Short flags can be combined, e.g. -ncb
        \\
        \\Test detection:
        \\  - Path patterns: tests/, test/, spec/, specs/, __tests__/, e2e/,
        \\    cypress/, playwright/, testing/, fixtures/
        \\  - Filename patterns: *_test.*, *_spec.*, *_tests.*, *.test.*, *.spec.*,
        \\    test_*.*, tests_*.*, *Test.{java,kt,scala,groovy}, *Tests.*,
        \\    *IT.*, *ITCase.*, conftest.py
        \\  - Rust inline: lines inside #[cfg(test)] mod ... { } blocks
        \\
        \\Default extensions:
    );
    try w.writeByte(' ');
    for (default_exts, 0..) |e, idx| {
        if (idx > 0) try w.writeByte(' ');
        try w.writeAll(e);
    }
    try w.writeByte('\n');
}

fn printVersion(w: *std.Io.Writer) !void {
    try w.print("sloc {s}\n", .{build_options.version});
}

fn splitCommaAppend(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    spec: []const u8,
) !void {
    var it = std.mem.splitScalar(u8, spec, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        const normalized = if (trimmed[0] == '.' and trimmed.len > 1) trimmed[1..] else trimmed;
        if (normalized.len == 0) continue;
        try out.append(allocator, normalized);
    }
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn asciiStartsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return haystack.len >= needle.len and asciiEqlIgnoreCase(haystack[0..needle.len], needle);
}

fn asciiEndsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return haystack.len >= needle.len and asciiEqlIgnoreCase(haystack[haystack.len - needle.len ..], needle);
}

fn basenameMatchesExt(base: []const u8, ext: []const u8) bool {
    if (ext.len == 0) return false;
    if (base.len <= ext.len + 1) return false;

    const dot = base.len - ext.len - 1;
    if (dot == 0 or base[dot] != '.') return false;

    return asciiEqlIgnoreCase(base[dot + 1 ..], ext);
}

fn matchedAllowedExt(path: []const u8, allowed: []const []const u8) ?[]const u8 {
    const base = std.fs.path.basename(path);
    var best: ?[]const u8 = null;
    for (allowed) |ext| {
        if (!basenameMatchesExt(base, ext)) continue;
        if (best == null or ext.len > best.?.len) best = ext;
    }
    return best;
}

fn runGit(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    max_bytes: usize,
) !?[]u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = max_bytes,
    }) catch return null;
    defer allocator.free(result.stderr);
    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(result.stdout);
                return null;
            }
            return result.stdout;
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }
}

fn isInsideGitRepo(allocator: std.mem.Allocator) bool {
    const stdout = runGit(allocator, &.{ "git", "rev-parse", "--is-inside-work-tree" }, 4096) catch return false;
    if (stdout == null) return false;
    allocator.free(stdout.?);
    return true;
}

fn matchesExtFilter(path: []const u8, allowed: []const []const u8) bool {
    return matchedAllowedExt(path, allowed) != null;
}

fn collectFilesGit(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    allowed: []const []const u8,
    seen: *std.StringHashMap(void),
) !void {
    const max = 128 * 1024 * 1024;
    const tracked_opt = try runGit(allocator, &.{ "git", "ls-files" }, max);
    const untracked_opt = try runGit(allocator, &.{ "git", "ls-files", "--others", "--exclude-standard" }, max);

    const sources = [_]?[]u8{ tracked_opt, untracked_opt };
    for (sources) |src_opt| {
        const src = src_opt orelse continue;
        var it = std.mem.splitScalar(u8, src, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            if (!matchesExtFilter(line, allowed)) continue;
            if (seen.contains(line)) continue;
            const copy = try allocator.dupe(u8, line);
            try seen.put(copy, {});
            try out.append(allocator, copy);
        }
    }
}

fn collectFilesWalk(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    allowed: []const []const u8,
) !void {
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!matchesExtFilter(entry.path, allowed)) continue;
        const copy = try allocator.dupe(u8, entry.path);
        try out.append(allocator, copy);
    }
}

fn buildAllowedExts(
    allocator: std.mem.Allocator,
    opts: *const Options,
) !std.ArrayList([]const u8) {
    var list: std.ArrayList([]const u8) = .empty;

    if (opts.only.items.len > 0) {
        for (opts.only.items) |spec| try splitCommaAppend(allocator, &list, spec);
        return list;
    }

    for (default_exts) |e| try list.append(allocator, e);
    for (opts.add.items) |spec| try splitCommaAppend(allocator, &list, spec);

    if (opts.exclude.items.len > 0) {
        var excluded: std.ArrayList([]const u8) = .empty;
        for (opts.exclude.items) |spec| try splitCommaAppend(allocator, &excluded, spec);

        var filtered: std.ArrayList([]const u8) = .empty;
        outer: for (list.items) |e| {
            for (excluded.items) |x| {
                if (asciiEqlIgnoreCase(e, x)) continue :outer;
            }
            try filtered.append(allocator, e);
        }
        return filtered;
    }

    return list;
}

fn uniqExtensions(
    allocator: std.mem.Allocator,
    files: []const FileCount,
) !std.ArrayList([]const u8) {
    var list: std.ArrayList([]const u8) = .empty;
    var seen = std.StringHashMap(void).init(allocator);
    for (files) |f| {
        const ext = f.ext;
        if (seen.contains(ext)) continue;
        try seen.put(ext, {});
        try list.append(allocator, ext);
    }
    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return list;
}

fn digitsU64(n: u64) usize {
    if (n == 0) return 1;
    var v = n;
    var d: usize = 0;
    while (v > 0) : (v /= 10) d += 1;
    return d;
}

fn commaWidth(n: u64) usize {
    const d = digitsU64(n);
    return d + (d - 1) / 3;
}

fn writeCommaU64(w: *std.Io.Writer, n: u64) !void {
    if (n == 0) {
        try w.writeByte('0');
        return;
    }
    var buf: [32]u8 = undefined;
    var i = buf.len;
    var v = n;
    var digits: usize = 0;
    while (v > 0) {
        if (digits > 0 and digits % 3 == 0) {
            i -= 1;
            buf[i] = ',';
        }
        i -= 1;
        buf[i] = @as(u8, @intCast('0' + (v % 10)));
        v /= 10;
        digits += 1;
    }
    try w.writeAll(buf[i..]);
}

fn padSpaces(w: *std.Io.Writer, n: usize) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) try w.writeByte(' ');
}

fn pathDirname(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| return path[0..idx];
    return ".";
}

fn lessByTotalDesc(_: void, a: FileCount, b: FileCount) bool {
    return a.total() > b.total();
}

const DisplayCount = struct {
    primary: u64,
    test_c: u64,
    comment: u64,
    blank: u64,

    fn total(self: DisplayCount) u64 {
        return self.primary + self.test_c + self.comment + self.blank;
    }
};

const ColumnWidths = struct {
    primary: usize,
    test_w: usize,
    comment: usize,
    blank: usize,
};

fn primaryLabel(opts: RenderOptions) []const u8 {
    return if (opts.split_tests) "CODE" else "LINES";
}

fn makeDisplayCount(
    code: u64,
    test_count: u64,
    comment: u64,
    blank: u64,
    opts: RenderOptions,
) DisplayCount {
    const shown_test = if (opts.split_tests) test_count else 0;
    const shown_comment = if (opts.show_comments) comment else 0;
    const shown_blank = if (opts.show_blanks) blank else 0;
    return .{
        .primary = code + if (opts.split_tests) 0 else test_count,
        .test_c = shown_test,
        .comment = shown_comment,
        .blank = shown_blank,
    };
}

fn visibleColumnWidth(widths: ColumnWidths, opts: RenderOptions) usize {
    var width = widths.primary;
    if (opts.split_tests) width += 2 + widths.test_w;
    if (opts.show_comments) width += 2 + widths.comment;
    if (opts.show_blanks) width += 2 + widths.blank;
    return width;
}

// ---------- styling ----------

const Color = struct {
    reset: []const u8 = "",
    bold: []const u8 = "",
    dim: []const u8 = "",
    cyan: []const u8 = "",
    blue: []const u8 = "",
    green: []const u8 = "",
    yellow: []const u8 = "",
    gray: []const u8 = "",
    magenta: []const u8 = "",

    fn init(enable: bool) Color {
        if (!enable) return .{};
        return .{
            .reset = "\x1b[0m",
            .bold = "\x1b[1m",
            .dim = "\x1b[2m",
            .cyan = "\x1b[36m",
            .blue = "\x1b[34m",
            .green = "\x1b[32m",
            .yellow = "\x1b[33m",
            .gray = "\x1b[90m",
            .magenta = "\x1b[35m",
        };
    }
};

fn colorEnabled(allocator: std.mem.Allocator) bool {
    if (std.process.hasEnvVar(allocator, "NO_COLOR") catch false) return false;
    return std.fs.File.stdout().isTty();
}

fn writeCodeNum(w: *std.Io.Writer, n: u64, width: usize, color: Color) !void {
    const cw = commaWidth(n);
    if (width > cw) try padSpaces(w, width - cw);
    if (n == 0) {
        try w.writeAll(color.dim);
        try w.writeByte('0');
        try w.writeAll(color.reset);
    } else {
        try w.writeAll(color.green);
        try writeCommaU64(w, n);
        try w.writeAll(color.reset);
    }
}

fn writeTestNum(w: *std.Io.Writer, n: u64, width: usize, color: Color) !void {
    const cw = commaWidth(n);
    if (width > cw) try padSpaces(w, width - cw);
    if (n == 0) {
        try w.writeAll(color.dim);
        try w.writeByte('0');
        try w.writeAll(color.reset);
    } else {
        try w.writeAll(color.yellow);
        try writeCommaU64(w, n);
        try w.writeAll(color.reset);
    }
}

fn writeCommentNum(w: *std.Io.Writer, n: u64, width: usize, color: Color) !void {
    const cw = commaWidth(n);
    if (width > cw) try padSpaces(w, width - cw);
    if (n == 0) {
        try w.writeAll(color.dim);
        try w.writeByte('0');
        try w.writeAll(color.reset);
    } else {
        try w.writeAll(color.magenta);
        try writeCommaU64(w, n);
        try w.writeAll(color.reset);
    }
}

fn writeBlankNum(w: *std.Io.Writer, n: u64, width: usize, color: Color) !void {
    const cw = commaWidth(n);
    if (width > cw) try padSpaces(w, width - cw);
    if (n == 0) {
        try w.writeAll(color.dim);
        try w.writeByte('0');
        try w.writeAll(color.reset);
    } else {
        try w.writeAll(color.cyan);
        try writeCommaU64(w, n);
        try w.writeAll(color.reset);
    }
}

fn writePlainPadded(w: *std.Io.Writer, n: u64, width: usize) !void {
    const cw = commaWidth(n);
    if (width > cw) try padSpaces(w, width - cw);
    try writeCommaU64(w, n);
}

fn writeRightHeader(w: *std.Io.Writer, label: []const u8, width: usize, color: Color) !void {
    if (width > label.len) try padSpaces(w, width - label.len);
    try w.writeAll(color.bold);
    try w.writeAll(label);
    try w.writeAll(color.reset);
}

fn writeLeftHeader(w: *std.Io.Writer, label: []const u8, color: Color) !void {
    try w.writeAll(color.bold);
    try w.writeAll(label);
    try w.writeAll(color.reset);
}

fn writeRule(w: *std.Io.Writer, width: usize, color: Color) !void {
    try w.writeAll(color.dim);
    var i: usize = 0;
    while (i < width) : (i += 1) try w.writeAll("─");
    try w.writeAll(color.reset);
    try w.writeByte('\n');
}

fn writeBar(w: *std.Io.Writer, n: u64, max: u64, width: usize, color: Color) !void {
    if (max == 0 or width == 0 or n == 0) return;
    const units: u64 = (n * @as(u64, width) * 8) / max;
    const full = units / 8;
    const frac = units % 8;
    const partials = [_][]const u8{ "", "▏", "▎", "▍", "▌", "▋", "▊", "▉" };

    try w.writeAll(color.blue);
    var i: u64 = 0;
    while (i < full) : (i += 1) try w.writeAll("█");
    if (frac > 0) try w.writeAll(partials[@intCast(frac)]);
    try w.writeAll(color.reset);
}

fn writeVisibleHeaders(
    w: *std.Io.Writer,
    widths: ColumnWidths,
    opts: RenderOptions,
    color: Color,
) !void {
    try writeRightHeader(w, primaryLabel(opts), widths.primary, color);
    if (opts.split_tests) {
        try w.writeAll("  ");
        try writeRightHeader(w, "TEST", widths.test_w, color);
    }
    if (opts.show_comments) {
        try w.writeAll("  ");
        try writeRightHeader(w, "COMMENT", widths.comment, color);
    }
    if (opts.show_blanks) {
        try w.writeAll("  ");
        try writeRightHeader(w, "BLANK", widths.blank, color);
    }
}

fn writeVisibleNums(
    w: *std.Io.Writer,
    counts: DisplayCount,
    widths: ColumnWidths,
    opts: RenderOptions,
    color: Color,
) !void {
    try writeCodeNum(w, counts.primary, widths.primary, color);
    if (opts.split_tests) {
        try w.writeAll("  ");
        try writeTestNum(w, counts.test_c, widths.test_w, color);
    }
    if (opts.show_comments) {
        try w.writeAll("  ");
        try writeCommentNum(w, counts.comment, widths.comment, color);
    }
    if (opts.show_blanks) {
        try w.writeAll("  ");
        try writeBlankNum(w, counts.blank, widths.blank, color);
    }
}

fn writeVisiblePlainNums(
    w: *std.Io.Writer,
    counts: DisplayCount,
    widths: ColumnWidths,
    opts: RenderOptions,
) !void {
    try writePlainPadded(w, counts.primary, widths.primary);
    if (opts.split_tests) {
        try w.writeAll("  ");
        try writePlainPadded(w, counts.test_c, widths.test_w);
    }
    if (opts.show_comments) {
        try w.writeAll("  ");
        try writePlainPadded(w, counts.comment, widths.comment);
    }
    if (opts.show_blanks) {
        try w.writeAll("  ");
        try writePlainPadded(w, counts.blank, widths.blank);
    }
}

// ---------- tree ----------

const Node = struct {
    name: []const u8,
    is_dir: bool,
    code: u64,
    test_c: u64,
    comment_c: u64,
    blank_c: u64,
    children: std.ArrayList(*Node),

    fn total(self: *const Node) u64 {
        return self.code + self.test_c + self.comment_c + self.blank_c;
    }
};

fn newNode(
    allocator: std.mem.Allocator,
    name: []const u8,
    is_dir: bool,
) !*Node {
    const n = try allocator.create(Node);
    n.* = .{
        .name = name,
        .is_dir = is_dir,
        .code = 0,
        .test_c = 0,
        .comment_c = 0,
        .blank_c = 0,
        .children = .empty,
    };
    return n;
}

fn getOrCreateChild(
    allocator: std.mem.Allocator,
    parent: *Node,
    name: []const u8,
    is_dir: bool,
) !*Node {
    for (parent.children.items) |c| {
        if (std.mem.eql(u8, c.name, name)) return c;
    }
    const n = try newNode(allocator, name, is_dir);
    try parent.children.append(allocator, n);
    return n;
}

fn buildTree(allocator: std.mem.Allocator, files: []const FileCount) !*Node {
    const root = try newNode(allocator, ".", true);
    for (files) |f| {
        root.code += f.code_count;
        root.test_c += f.test_count;
        root.comment_c += f.comment_count;
        root.blank_c += f.blank_count;

        var cursor = root;
        var it = std.mem.splitScalar(u8, f.path, '/');
        var part_opt = it.next();
        while (part_opt) |part| {
            const next = it.next();
            const is_file = (next == null);
            const node = try getOrCreateChild(allocator, cursor, part, !is_file);
            node.code += f.code_count;
            node.test_c += f.test_count;
            node.comment_c += f.comment_count;
            node.blank_c += f.blank_count;
            cursor = node;
            part_opt = next;
        }
    }
    return root;
}

fn sortTreeAlpha(node: *Node) void {
    std.mem.sort(*Node, node.children.items, {}, struct {
        fn lt(_: void, a: *Node, b: *Node) bool {
            // dirs first, then files; alphabetical within each group
            if (a.is_dir and !b.is_dir) return true;
            if (!a.is_dir and b.is_dir) return false;
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    for (node.children.items) |c| sortTreeAlpha(c);
}

fn sortTreeDesc(node: *Node) void {
    std.mem.sort(*Node, node.children.items, {}, struct {
        fn lt(_: void, a: *Node, b: *Node) bool {
            if (a.total() != b.total()) return a.total() > b.total();
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    for (node.children.items) |c| sortTreeDesc(c);
}

fn printTree(
    w: *std.Io.Writer,
    allocator: std.mem.Allocator,
    node: *const Node,
    prefix: []const u8,
    is_last: bool,
    is_root: bool,
    widths: ColumnWidths,
    opts: RenderOptions,
    color: Color,
) !void {
    const counts = makeDisplayCount(node.code, node.test_c, node.comment_c, node.blank_c, opts);
    try writeVisibleNums(w, counts, widths, opts, color);
    try w.writeAll("  ");

    if (is_root) {
        try w.writeAll(color.bold);
        try w.writeAll(node.name);
        try w.writeAll(color.reset);
        try w.writeByte('\n');
    } else {
        try w.writeAll(color.gray);
        try w.writeAll(prefix);
        try w.writeAll(if (is_last) "└── " else "├── ");
        try w.writeAll(color.reset);
        if (node.is_dir) {
            try w.writeAll(color.cyan);
            try w.writeAll(node.name);
            try w.writeByte('/');
            try w.writeAll(color.reset);
        } else {
            try w.writeAll(node.name);
        }
        try w.writeByte('\n');
    }

    const new_prefix = if (is_root)
        try allocator.dupe(u8, "")
    else blk: {
        const ext = if (is_last) "    " else "│   ";
        break :blk try std.mem.concat(allocator, u8, &.{ prefix, ext });
    };

    for (node.children.items, 0..) |child, i| {
        const child_last = (i == node.children.items.len - 1);
        try printTree(w, allocator, child, new_prefix, child_last, false, widths, opts, color);
    }
}

// ---------- summary ----------

const ExtRow = struct {
    ext: []const u8,
    code: u64,
    test_c: u64,
    comment_c: u64,
    blank_c: u64,

    fn total(self: ExtRow) u64 {
        return self.code + self.test_c + self.comment_c + self.blank_c;
    }
};

fn printExtensionTable(
    w: *std.Io.Writer,
    allocator: std.mem.Allocator,
    files: []const FileCount,
    total_code: u64,
    total_test: u64,
    total_comment: u64,
    total_blank: u64,
    descending: bool,
    opts: RenderOptions,
    color: Color,
) !void {
    const exts = try uniqExtensions(allocator, files);
    const rows = try allocator.alloc(ExtRow, exts.items.len);
    for (exts.items, 0..) |e, i| {
        var ec: u64 = 0;
        var et: u64 = 0;
        var em: u64 = 0;
        var eb: u64 = 0;
        for (files) |f| {
            if (!asciiEqlIgnoreCase(f.ext, e)) continue;
            ec += f.code_count;
            et += f.test_count;
            em += f.comment_count;
            eb += f.blank_count;
        }
        rows[i] = .{ .ext = e, .code = ec, .test_c = et, .comment_c = em, .blank_c = eb };
    }

    if (descending) {
        std.mem.sort(ExtRow, rows, {}, struct {
            fn lt(_: void, a: ExtRow, b: ExtRow) bool {
                if (a.total() != b.total()) return a.total() > b.total();
                return std.mem.lessThan(u8, a.ext, b.ext);
            }
        }.lt);
    } else {
        std.mem.sort(ExtRow, rows, {}, struct {
            fn lt(_: void, a: ExtRow, b: ExtRow) bool {
                return std.mem.lessThan(u8, a.ext, b.ext);
            }
        }.lt);
    }

    const total_counts = makeDisplayCount(total_code, total_test, total_comment, total_blank, opts);
    var widths = ColumnWidths{
        .primary = @max(commaWidth(total_counts.primary), primaryLabel(opts).len),
        .test_w = @max(commaWidth(total_counts.test_c), 4),
        .comment = @max(commaWidth(total_counts.comment), 7),
        .blank = @max(commaWidth(total_counts.blank), 5),
    };
    var max_ext: usize = 4; // "TYPE"
    for (rows) |r| {
        const counts = makeDisplayCount(r.code, r.test_c, r.comment_c, r.blank_c, opts);
        widths.primary = @max(widths.primary, commaWidth(counts.primary));
        widths.test_w = @max(widths.test_w, commaWidth(counts.test_c));
        widths.comment = @max(widths.comment, commaWidth(counts.comment));
        widths.blank = @max(widths.blank, commaWidth(counts.blank));
        max_ext = @max(max_ext, r.ext.len + 1); // +1 for leading '.'
    }
    const bar_width: usize = 20;

    var max_total: u64 = 0;
    for (rows) |r| {
        const counts = makeDisplayCount(r.code, r.test_c, r.comment_c, r.blank_c, opts);
        max_total = @max(max_total, counts.total());
    }

    // Header row
    try writeVisibleHeaders(w, widths, opts, color);
    try w.writeAll("  ");
    try writeLeftHeader(w, "TYPE", color);
    try w.writeByte('\n');

    const header_rule_width = visibleColumnWidth(widths, opts) + 2 + max_ext + 1 + bar_width;
    try writeRule(w, header_rule_width, color);

    for (rows) |r| {
        const counts = makeDisplayCount(r.code, r.test_c, r.comment_c, r.blank_c, opts);
        try writeVisibleNums(w, counts, widths, opts, color);
        try w.writeAll("  ");
        try w.writeAll(color.dim);
        try w.writeByte('.');
        try w.writeAll(color.reset);
        try w.writeAll(r.ext);
        const written = r.ext.len + 1;
        if (max_ext > written) try padSpaces(w, max_ext - written);
        try w.writeByte(' ');
        try writeBar(w, r.total(), max_total, bar_width, color);
        try w.writeByte('\n');
    }

    try writeRule(w, visibleColumnWidth(widths, opts), color);

    try w.writeAll(color.bold);
    try writeVisiblePlainNums(w, total_counts, widths, opts);
    try w.writeAll("  TOTAL");
    try w.writeAll(color.reset);
    try w.writeByte('\n');
}

// ---------- main ----------

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: [8192]u8 = undefined;
    var stdout_file = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_file.interface;

    const argv = try std.process.argsAlloc(allocator);

    var opts = parseArgs(allocator, argv) catch |err| switch (err) {
        ArgError.MissingValue, ArgError.UnknownOption => {
            try printHelp(stdout);
            try stdout.flush();
            std.process.exit(2);
        },
        else => return err,
    };

    if (opts.help) {
        try printHelp(stdout);
        try stdout.flush();
        return;
    }

    if (opts.version) {
        try printVersion(stdout);
        try stdout.flush();
        return;
    }

    const color = Color.init(colorEnabled(allocator));
    const count_opts = CountOptions{
        .show_comments = opts.show_comments,
        .show_blanks = opts.show_blanks,
        .count_symbol_only = opts.count_symbol_only,
    };
    const render_opts = RenderOptions{
        .split_tests = opts.split_tests,
        .show_comments = opts.show_comments,
        .show_blanks = opts.show_blanks,
    };

    const allowed = try buildAllowedExts(allocator, &opts);

    var files_raw: std.ArrayList([]const u8) = .empty;
    if (isInsideGitRepo(allocator)) {
        var seen = std.StringHashMap(void).init(allocator);
        try collectFilesGit(allocator, &files_raw, allowed.items, &seen);
    } else {
        try collectFilesWalk(allocator, &files_raw, allowed.items);
    }

    var files: std.ArrayList(FileCount) = .empty;
    var total_code: u64 = 0;
    var total_test: u64 = 0;
    var total_comment: u64 = 0;
    var total_blank: u64 = 0;

    for (files_raw.items) |path| {
        const content = std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024 * 1024) catch continue;
        const matched_ext = matchedAllowedExt(path, allowed.items) orelse continue;
        const plugin = lang_plugins.resolve(matched_ext);
        const force_test = lang_plugins.isTestPath(path, plugin);
        const c = lang_plugins.countFile(content, force_test, plugin, count_opts);
        total_code += c.code_count;
        total_test += c.test_count;
        total_comment += c.comment_count;
        total_blank += c.blank_count;
        try files.append(allocator, .{
            .path = path,
            .ext = matched_ext,
            .test_count = c.test_count,
            .comment_count = c.comment_count,
            .blank_count = c.blank_count,
            .code_count = c.code_count,
        });
    }

    if (files.items.len == 0) {
        try w_noFiles(stdout, color);
        try stdout.flush();
        return;
    }

    if (!opts.summary) {
        const total_counts = makeDisplayCount(total_code, total_test, total_comment, total_blank, render_opts);
        var widths = ColumnWidths{
            .primary = @max(commaWidth(total_counts.primary), primaryLabel(render_opts).len),
            .test_w = @max(commaWidth(total_counts.test_c), 4),
            .comment = @max(commaWidth(total_counts.comment), 7),
            .blank = @max(commaWidth(total_counts.blank), 5),
        };
        for (files.items) |f| {
            const counts = makeDisplayCount(f.code_count, f.test_count, f.comment_count, f.blank_count, render_opts);
            widths.primary = @max(widths.primary, commaWidth(counts.primary));
            widths.test_w = @max(widths.test_w, commaWidth(counts.test_c));
            widths.comment = @max(widths.comment, commaWidth(counts.comment));
            widths.blank = @max(widths.blank, commaWidth(counts.blank));
        }

        try writeVisibleHeaders(stdout, widths, render_opts, color);
        try stdout.writeAll("  ");
        try writeLeftHeader(stdout, "PATH", color);
        try stdout.writeByte('\n');
        try writeRule(stdout, visibleColumnWidth(widths, render_opts) + 2 + 32, color);

        if (opts.descending) {
            try writeVisibleNums(stdout, total_counts, widths, render_opts, color);
            try stdout.writeAll("  ");
            try stdout.writeAll(color.bold);
            try stdout.writeAll(".");
            try stdout.writeAll(color.reset);
            try stdout.writeByte('\n');

            const sorted = try allocator.alloc(FileCount, files.items.len);
            @memcpy(sorted, files.items);
            std.mem.sort(FileCount, sorted, {}, lessByTotalDesc);
            for (sorted) |f| {
                const counts = makeDisplayCount(f.code_count, f.test_count, f.comment_count, f.blank_count, render_opts);
                try writeVisibleNums(stdout, counts, widths, render_opts, color);
                try stdout.writeAll("  ");
                if (lang_plugins.isTestPath(f.path, lang_plugins.resolve(f.ext))) {
                    try stdout.writeAll(color.yellow);
                    try stdout.writeAll(f.path);
                    try stdout.writeAll(color.reset);
                } else {
                    try stdout.writeAll(f.path);
                }
                try stdout.writeByte('\n');
            }
        } else {
            const root = try buildTree(allocator, files.items);
            sortTreeAlpha(root);
            try printTree(stdout, allocator, root, "", false, true, widths, render_opts, color);
        }
        try stdout.writeByte('\n');
    }

    try printExtensionTable(
        stdout,
        allocator,
        files.items,
        total_code,
        total_test,
        total_comment,
        total_blank,
        opts.descending,
        render_opts,
        color,
    );

    try stdout.flush();
}

fn w_noFiles(w: *std.Io.Writer, color: Color) !void {
    try w.writeAll(color.dim);
    try w.writeAll("No matching files.\n");
    try w.writeAll(color.reset);
}

// ---------- tests ----------

test "matchedAllowedExt - case insensitive and multi-dot" {
    const allowed = [_][]const u8{ "rs", "app.src", "py" };

    try std.testing.expectEqualStrings("rs", matchedAllowedExt("src/LIB.RS", &allowed).?);
    try std.testing.expectEqualStrings("app.src", matchedAllowedExt("src/demo.APP.SRC", &allowed).?);
    try std.testing.expectEqualStrings("py", matchedAllowedExt("src/tool.Py", &allowed).?);
    try std.testing.expect(matchedAllowedExt("src/.rs", &allowed) == null);
}

test "splitCommaAppend - strips leading dot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var list: std.ArrayList([]const u8) = .empty;
    try splitCommaAppend(arena.allocator(), &list, ".py, app.src, .RS");

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqualStrings("py", list.items[0]);
    try std.testing.expectEqualStrings("app.src", list.items[1]);
    try std.testing.expectEqualStrings("RS", list.items[2]);
}

test "commaWidth and writeCommaU64" {
    try std.testing.expectEqual(@as(usize, 1), commaWidth(0));
    try std.testing.expectEqual(@as(usize, 1), commaWidth(9));
    try std.testing.expectEqual(@as(usize, 3), commaWidth(999));
    try std.testing.expectEqual(@as(usize, 5), commaWidth(1000));
    try std.testing.expectEqual(@as(usize, 9), commaWidth(1000000));
}

test "parseArgs - version flag" {
    const argv = [_][]const u8{ "sloc", "--version" };
    const opts = try parseArgs(std.testing.allocator, &argv);
    try std.testing.expect(opts.version);
}

test "parseArgs - count toggles and short bundle" {
    const argv = [_][]const u8{ "sloc", "-ncbp", "--comments" };
    const opts = try parseArgs(std.testing.allocator, &argv);
    try std.testing.expect(!opts.split_tests);
    try std.testing.expect(opts.show_comments);
    try std.testing.expect(opts.show_blanks);
    try std.testing.expect(opts.count_symbol_only);
}
