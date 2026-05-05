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
    line_authors: bool = false,
    churn: bool = false,
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
        } else if (std.mem.eql(u8, a, "--line-authors")) {
            opts.line_authors = true;
        } else if (std.mem.eql(u8, a, "--churn")) {
            opts.churn = true;
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
        'l' => opts.line_authors = true,
        'r' => opts.churn = true,
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
        \\Usage: sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-n] [-c] [-b] [-p] [-l] [-r]
        \\            [--split-tests|--no-split-tests] [--comments|--no-comments]
        \\            [--blanks|--no-blanks] [--count-symbols|--no-count-symbols]
        \\            [--line-authors] [--churn] [-V] [-h]
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
        \\  -l, --line-authors      Use git blame to color summary bars by line author
        \\  -r, --churn             Use git log to show added/deleted churn by file type
        \\      --split-tests       Show separate code and test columns (default: on)
        \\      --comments          Show comment-line counts (default: on)
        \\      --no-blanks         Exclude blank lines from counts and output
        \\      --no-count-symbols  Exclude symbol-only lines from counts
        \\  -V, --version           Display version information
        \\  -h, --help              Display this help message
        \\                          Short flags can be combined, e.g. -ncblr
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

const ChurnExtMatcher = struct {
    exact: std.StringHashMap([]const u8),
    dotted: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, allowed: []const []const u8) !ChurnExtMatcher {
        var matcher = ChurnExtMatcher{
            .exact = std.StringHashMap([]const u8).init(allocator),
            .dotted = .empty,
        };
        for (allowed) |ext| {
            if (std.mem.indexOfScalar(u8, ext, '.') != null) {
                try matcher.dotted.append(allocator, ext);
                continue;
            }
            const normalized = try allocator.dupe(u8, ext);
            _ = std.ascii.lowerString(normalized, normalized);
            try matcher.exact.put(normalized, ext);
        }
        return matcher;
    }

    fn match(self: *const ChurnExtMatcher, path: []const u8) ?[]const u8 {
        const base = std.fs.path.basename(path);

        var best: ?[]const u8 = null;
        for (self.dotted.items) |ext| {
            if (!basenameMatchesExt(base, ext)) continue;
            if (best == null or ext.len > best.?.len) best = ext;
        }
        if (best != null) return best;

        const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return null;
        if (dot == 0 or dot == base.len - 1) return null;
        const raw_ext = base[dot + 1 ..];
        var buf: [256]u8 = undefined;
        if (raw_ext.len > buf.len) return null;
        const normalized = buf[0..raw_ext.len];
        _ = std.ascii.lowerString(normalized, raw_ext);
        return self.exact.get(normalized);
    }
};

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

fn scaledBlockWidth(n: u64, max: u64, width: usize) usize {
    if (max == 0 or width == 0 or n == 0) return 0;
    const scaled = (@as(u128, n) * @as(u128, width) + @as(u128, max) / 2) / @as(u128, max);
    return @max(1, @min(width, @as(usize, @intCast(scaled))));
}

fn segmentEnd(cumulative: u64, total: u64, width: usize) usize {
    if (total == 0 or width == 0) return 0;
    const scaled = (@as(u128, cumulative) * @as(u128, width) + @as(u128, total) / 2) / @as(u128, total);
    return @min(width, @as(usize, @intCast(scaled)));
}

fn authorColor(author: []const u8, color: Color) []const u8 {
    const palette = [_][]const u8{
        color.green,
        color.yellow,
        color.magenta,
        color.cyan,
        color.blue,
    };
    const hash = std.hash.Wyhash.hash(0, author);
    return palette[@intCast(hash % palette.len)];
}

fn writeBlockSegment(w: *std.Io.Writer, width: usize, segment_color: []const u8, color: Color) !void {
    if (width == 0) return;
    try w.writeAll(segment_color);
    var i: usize = 0;
    while (i < width) : (i += 1) try w.writeAll("█");
    try w.writeAll(color.reset);
}

fn authorRowsTotal(rows: []const AuthorRow, ext: []const u8) u64 {
    var total: u64 = 0;
    for (rows) |row| {
        if (std.mem.eql(u8, row.ext, ext)) total += row.total();
    }
    return total;
}

fn writeAuthorBar(
    w: *std.Io.Writer,
    rows: []const AuthorRow,
    ext: []const u8,
    row_total: u64,
    max_total: u64,
    width: usize,
    color: Color,
) !void {
    const graph_width = scaledBlockWidth(row_total, max_total, width);
    if (graph_width == 0) return;

    const author_total = authorRowsTotal(rows, ext);
    const segment_total = @max(row_total, author_total);
    var cumulative: u64 = 0;
    var previous_end: usize = 0;

    for (rows) |row| {
        if (!std.mem.eql(u8, row.ext, ext)) continue;
        const row_count = row.total();
        if (row_count == 0) continue;
        cumulative += row_count;
        const end = segmentEnd(cumulative, segment_total, graph_width);
        try writeBlockSegment(w, end - previous_end, authorColor(row.author, color), color);
        previous_end = end;
    }

    if (row_total > author_total) {
        cumulative += row_total - author_total;
        const end = segmentEnd(cumulative, segment_total, graph_width);
        try writeBlockSegment(w, end - previous_end, color.gray, color);
        previous_end = end;
    }

    if (previous_end < graph_width) {
        try writeBlockSegment(w, graph_width - previous_end, color.gray, color);
    }
}

fn writeAuthorLegend(
    w: *std.Io.Writer,
    rows: []const AuthorRow,
    ext: []const u8,
    row_total: u64,
    color: Color,
) !void {
    if (row_total == 0) return;

    const max_authors: usize = 5;
    var shown: usize = 0;
    var hidden: usize = 0;
    var hidden_total: u64 = 0;
    var author_total: u64 = 0;
    var wrote_any = false;

    for (rows) |row| {
        if (!std.mem.eql(u8, row.ext, ext)) continue;
        const row_count = row.total();
        if (row_count == 0) continue;
        author_total += row_count;
        if (shown >= max_authors) {
            hidden += 1;
            hidden_total += row_count;
            continue;
        }
        if (wrote_any) try w.writeAll(", ");
        try w.writeAll(authorColor(row.author, color));
        try w.writeAll(row.author);
        try w.writeAll(color.reset);
        try w.writeByte(' ');
        try writePercentCell(w, row_count, row_total, percentCellWidth(row_count, row_total));
        shown += 1;
        wrote_any = true;
    }

    if (hidden > 0) {
        if (wrote_any) try w.writeAll(", ");
        try w.print("+{d} more ", .{hidden});
        try writePercentCell(w, hidden_total, row_total, percentCellWidth(hidden_total, row_total));
        wrote_any = true;
    }

    if (row_total > author_total) {
        if (wrote_any) try w.writeAll(", ");
        try w.writeAll(color.gray);
        try w.writeAll("unattributed");
        try w.writeAll(color.reset);
        try w.writeByte(' ');
        try writePercentCell(w, row_total - author_total, row_total, percentCellWidth(row_total - author_total, row_total));
    }
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
    added: u64 = 0,
    deleted: u64 = 0,

    fn total(self: ExtRow) u64 {
        return self.code + self.test_c + self.comment_c + self.blank_c;
    }

    fn churnTotal(self: ExtRow) u64 {
        return self.added + self.deleted;
    }

    fn net(self: ExtRow) i128 {
        return @as(i128, @intCast(self.added)) - @as(i128, @intCast(self.deleted));
    }
};

fn churnForExt(rows: []const ChurnRow, ext: []const u8) ChurnRow {
    for (rows) |row| {
        if (std.mem.eql(u8, row.ext, ext)) return row;
    }
    return .{ .ext = ext };
}

fn summaryExtensions(
    allocator: std.mem.Allocator,
    files: []const FileCount,
    churn_rows: []const ChurnRow,
) !std.ArrayList([]const u8) {
    var list: std.ArrayList([]const u8) = .empty;
    var seen = std.StringHashMap(void).init(allocator);

    for (files) |f| {
        if (seen.contains(f.ext)) continue;
        try seen.put(f.ext, {});
        try list.append(allocator, f.ext);
    }

    for (churn_rows) |row| {
        if (seen.contains(row.ext)) continue;
        try seen.put(row.ext, {});
        try list.append(allocator, row.ext);
    }

    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return list;
}

fn printExtensionTable(
    w: *std.Io.Writer,
    allocator: std.mem.Allocator,
    files: []const FileCount,
    author_rows_opt: ?[]const AuthorRow,
    churn_rows_opt: ?[]const ChurnRow,
    total_code: u64,
    total_test: u64,
    total_comment: u64,
    total_blank: u64,
    descending: bool,
    opts: RenderOptions,
    color: Color,
) !void {
    const empty_author_rows = [_]AuthorRow{};
    const author_rows = author_rows_opt orelse empty_author_rows[0..];
    const show_author_bars = author_rows_opt != null;
    const empty_churn_rows = [_]ChurnRow{};
    const churn_rows = churn_rows_opt orelse empty_churn_rows[0..];
    const show_churn = churn_rows_opt != null;

    const exts = try summaryExtensions(allocator, files, churn_rows);
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
        const churn = churnForExt(churn_rows, e);
        rows[i] = .{
            .ext = e,
            .code = ec,
            .test_c = et,
            .comment_c = em,
            .blank_c = eb,
            .added = churn.added,
            .deleted = churn.deleted,
        };
    }

    if (descending) {
        std.mem.sort(ExtRow, rows, {}, struct {
            fn lt(_: void, a: ExtRow, b: ExtRow) bool {
                if (a.total() != b.total()) return a.total() > b.total();
                if (a.churnTotal() != b.churnTotal()) return a.churnTotal() > b.churnTotal();
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
    var total_added: u64 = 0;
    var total_deleted: u64 = 0;
    for (churn_rows) |row| {
        total_added += row.added;
        total_deleted += row.deleted;
    }
    const total_net = @as(i128, @intCast(total_added)) - @as(i128, @intCast(total_deleted));
    var added_width: usize = @max(commaWidth(total_added), 5);
    var deleted_width: usize = @max(commaWidth(total_deleted), 7);
    var net_width: usize = @max(commaWidthI128(total_net), 3);
    var churn_width: usize = @max(percentCellWidth(total_deleted, total_added), 5);
    for (rows) |r| {
        const counts = makeDisplayCount(r.code, r.test_c, r.comment_c, r.blank_c, opts);
        widths.primary = @max(widths.primary, commaWidth(counts.primary));
        widths.test_w = @max(widths.test_w, commaWidth(counts.test_c));
        widths.comment = @max(widths.comment, commaWidth(counts.comment));
        widths.blank = @max(widths.blank, commaWidth(counts.blank));
        added_width = @max(added_width, commaWidth(r.added));
        deleted_width = @max(deleted_width, commaWidth(r.deleted));
        net_width = @max(net_width, commaWidthI128(r.net()));
        churn_width = @max(churn_width, percentCellWidth(r.deleted, r.added));
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
    if (show_churn) {
        try w.writeAll("  ");
        try writeRightHeader(w, "ADDED", added_width, color);
        try w.writeAll("  ");
        try writeRightHeader(w, "DELETED", deleted_width, color);
        try w.writeAll("  ");
        try writeRightHeader(w, "NET", net_width, color);
        try w.writeAll("  ");
        try writeRightHeader(w, "CHURN", churn_width, color);
    }
    try w.writeAll("  ");
    try writeLeftHeader(w, "TYPE", color);
    if (show_author_bars) {
        if (max_ext > 4) try padSpaces(w, max_ext - 4);
        try w.writeAll("  ");
        try writeLeftHeader(w, "AUTHORS", color);
    }
    try w.writeByte('\n');

    const churn_rule_width = if (show_churn)
        @as(usize, 2) + added_width + 2 + deleted_width + 2 + net_width + 2 + churn_width
    else
        @as(usize, 0);
    const header_rule_width = visibleColumnWidth(widths, opts) + churn_rule_width + 2 + max_ext + 1 + bar_width +
        if (show_author_bars) @as(usize, 24) else @as(usize, 0);
    try writeRule(w, header_rule_width, color);

    for (rows) |r| {
        const counts = makeDisplayCount(r.code, r.test_c, r.comment_c, r.blank_c, opts);
        try writeVisibleNums(w, counts, widths, opts, color);
        if (show_churn) {
            try w.writeAll("  ");
            try writeCodeNum(w, r.added, added_width, color);
            try w.writeAll("  ");
            try writeCommentNum(w, r.deleted, deleted_width, color);
            try w.writeAll("  ");
            try writeNetNum(w, r.net(), net_width, color);
            try w.writeAll("  ");
            try writePercentCell(w, r.deleted, r.added, churn_width);
        }
        try w.writeAll("  ");
        try w.writeAll(color.dim);
        try w.writeByte('.');
        try w.writeAll(color.reset);
        try w.writeAll(r.ext);
        const written = r.ext.len + 1;
        if (max_ext > written) try padSpaces(w, max_ext - written);
        try w.writeByte(' ');
        if (show_author_bars) {
            try writeAuthorBar(w, author_rows, r.ext, counts.total(), max_total, bar_width, color);
            try w.writeAll("  ");
            try writeAuthorLegend(w, author_rows, r.ext, counts.total(), color);
        } else {
            try writeBar(w, r.total(), max_total, bar_width, color);
        }
        try w.writeByte('\n');
    }

    try writeRule(w, visibleColumnWidth(widths, opts) + churn_rule_width, color);

    try w.writeAll(color.bold);
    try writeVisiblePlainNums(w, total_counts, widths, opts);
    if (show_churn) {
        try w.writeAll("  ");
        try writePlainPadded(w, total_added, added_width);
        try w.writeAll("  ");
        try writePlainPadded(w, total_deleted, deleted_width);
        try w.writeAll("  ");
        if (net_width > commaWidthI128(total_net)) try padSpaces(w, net_width - commaWidthI128(total_net));
        try writeCommaI128(w, total_net);
        try w.writeAll("  ");
        try writePercentCell(w, total_deleted, total_added, churn_width);
    }
    try w.writeAll("  TOTAL");
    try w.writeAll(color.reset);
    try w.writeByte('\n');
}

// ---------- git reports ----------

const AuthorRow = struct {
    ext: []const u8,
    author: []const u8,
    code: u64 = 0,
    test_c: u64 = 0,
    comment_c: u64 = 0,
    blank_c: u64 = 0,

    fn total(self: AuthorRow) u64 {
        return self.code + self.test_c + self.comment_c + self.blank_c;
    }
};

const KindCounts = struct {
    code: u64 = 0,
    test_c: u64 = 0,
    comment_c: u64 = 0,
    blank_c: u64 = 0,

    fn total(self: KindCounts) u64 {
        return self.code + self.test_c + self.comment_c + self.blank_c;
    }
};

const BlameContext = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList(AuthorRow) = .empty,
    index: std.StringHashMap(usize),
    mutex: std.Thread.Mutex = .{},
    had_error: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn init(allocator: std.mem.Allocator) BlameContext {
        return .{
            .allocator = allocator,
            .index = std.StringHashMap(usize).init(allocator),
        };
    }
};

const ChurnRow = struct {
    ext: []const u8,
    added: u64 = 0,
    deleted: u64 = 0,
};

fn percentTenths(numerator: u64, denominator: u64) u64 {
    if (denominator == 0) return 0;
    const scaled = @as(u128, numerator) * 1000 + @as(u128, denominator) / 2;
    return @intCast(scaled / @as(u128, denominator));
}

fn percentWidthTenths(tenths: u64) usize {
    return digitsU64(tenths / 10) + 3; // integer part, '.', one decimal, '%'
}

fn percentCellWidth(numerator: u64, denominator: u64) usize {
    if (denominator == 0) return 3; // n/a
    return percentWidthTenths(percentTenths(numerator, denominator));
}

fn writePercentCell(
    w: *std.Io.Writer,
    numerator: u64,
    denominator: u64,
    width: usize,
) !void {
    if (denominator == 0) {
        if (width > 3) try padSpaces(w, width - 3);
        try w.writeAll("n/a");
        return;
    }

    const tenths = percentTenths(numerator, denominator);
    const cw = percentWidthTenths(tenths);
    if (width > cw) try padSpaces(w, width - cw);
    try w.print("{d}.{d}%", .{ tenths / 10, tenths % 10 });
}

fn commaWidthI128(n: i128) usize {
    if (n < 0) return 1 + commaWidth(@intCast(-n));
    return commaWidth(@intCast(n));
}

fn writeCommaI128(w: *std.Io.Writer, n: i128) !void {
    if (n < 0) {
        try w.writeByte('-');
        try writeCommaU64(w, @intCast(-n));
    } else {
        try writeCommaU64(w, @intCast(n));
    }
}

fn writeNetNum(w: *std.Io.Writer, n: i128, width: usize, color: Color) !void {
    const cw = commaWidthI128(n);
    if (width > cw) try padSpaces(w, width - cw);
    if (n < 0) {
        try w.writeAll(color.magenta);
        try writeCommaI128(w, n);
        try w.writeAll(color.reset);
    } else if (n == 0) {
        try w.writeAll(color.dim);
        try w.writeByte('0');
        try w.writeAll(color.reset);
    } else {
        try w.writeAll(color.green);
        try writeCommaI128(w, n);
        try w.writeAll(color.reset);
    }
}

fn makePairKey(buf: []u8, ext: []const u8, author: []const u8) ?[]const u8 {
    const need = ext.len + 1 + author.len;
    if (need > buf.len) return null;
    @memcpy(buf[0..ext.len], ext);
    buf[ext.len] = 0x1f;
    @memcpy(buf[ext.len + 1 .. need], author);
    return buf[0..need];
}

fn dupePairKey(
    allocator: std.mem.Allocator,
    ext: []const u8,
    author: []const u8,
) ![]const u8 {
    const out = try allocator.alloc(u8, ext.len + 1 + author.len);
    @memcpy(out[0..ext.len], ext);
    out[ext.len] = 0x1f;
    @memcpy(out[ext.len + 1 ..], author);
    return out;
}

fn addKindToCounts(counts: *KindCounts, kind: lang_plugins.LineKind) void {
    switch (kind) {
        .skipped => {},
        .code => {
            counts.code += 1;
        },
        .test_line => {
            counts.test_c += 1;
        },
        .comment => {
            counts.comment_c += 1;
        },
        .blank => {
            counts.blank_c += 1;
        },
    }
}

fn addCountsToAuthorRow(row: *AuthorRow, counts: KindCounts) void {
    row.code += counts.code;
    row.test_c += counts.test_c;
    row.comment_c += counts.comment_c;
    row.blank_c += counts.blank_c;
}

fn countKindsRange(kinds: []const lang_plugins.LineKind, start_line: usize, line_count: usize) KindCounts {
    if (start_line == 0 or line_count == 0) return .{};
    const start = start_line - 1;
    if (start >= kinds.len) return .{};
    const end = @min(kinds.len, start + line_count);

    var counts = KindCounts{};
    for (kinds[start..end]) |kind| addKindToCounts(&counts, kind);
    return counts;
}

fn addAuthorCounts(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(AuthorRow),
    index: *std.StringHashMap(usize),
    ext: []const u8,
    author: []const u8,
    counts: KindCounts,
) !void {
    if (counts.total() == 0) return;

    var key_buf: [512]u8 = undefined;
    if (makePairKey(&key_buf, ext, author)) |key| {
        if (index.get(key)) |row_idx| {
            addCountsToAuthorRow(&rows.items[row_idx], counts);
            return;
        }
    } else {
        for (rows.items) |*row| {
            if (std.mem.eql(u8, row.ext, ext) and std.mem.eql(u8, row.author, author)) {
                addCountsToAuthorRow(row, counts);
                return;
            }
        }
    }

    const author_copy = try allocator.dupe(u8, author);
    const key_copy = try dupePairKey(allocator, ext, author_copy);
    try index.put(key_copy, rows.items.len);
    try rows.append(allocator, .{ .ext = ext, .author = author_copy });
    addCountsToAuthorRow(&rows.items[rows.items.len - 1], counts);
}

const BlameFileState = struct {
    path: []const u8,
    ext: []const u8,
    kinds: []const lang_plugins.LineKind,
};

const BlameGroup = struct {
    commit: []const u8,
    result_line: usize,
    line_count: usize,
};

fn parseBlameGroupHeader(line: []const u8) ?BlameGroup {
    var fields = std.mem.splitScalar(u8, line, ' ');
    const commit = fields.next() orelse return null;
    const source_line_s = fields.next() orelse return null;
    const result_line_s = fields.next() orelse return null;
    const line_count_s = fields.next() orelse return null;
    if (commit.len != 40 and commit.len != 64) return null;
    for (commit) |c| {
        if (!std.ascii.isHex(c)) return null;
    }
    _ = std.fmt.parseUnsigned(usize, source_line_s, 10) catch return null;
    const result_line = std.fmt.parseUnsigned(usize, result_line_s, 10) catch return null;
    const line_count = std.fmt.parseUnsigned(usize, line_count_s, 10) catch return null;
    return .{
        .commit = commit,
        .result_line = result_line,
        .line_count = line_count,
    };
}

fn addAuthorCountsLocked(ctx: *BlameContext, ext: []const u8, author: []const u8, counts: KindCounts) !void {
    if (counts.total() == 0) return;
    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    try addAuthorCounts(ctx.allocator, &ctx.rows, &ctx.index, ext, author, counts);
}

fn parseBlameIncrementalOutput(
    ctx: *BlameContext,
    state: *const BlameFileState,
    blame: []const u8,
) !void {
    var commit_authors = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    defer commit_authors.deinit();

    var current_group: ?BlameGroup = null;
    var current_author: ?[]const u8 = null;

    var it = std.mem.splitScalar(u8, blame, '\n');
    while (it.next()) |line| {
        if (parseBlameGroupHeader(line)) |group| {
            current_group = group;
            current_author = commit_authors.get(group.commit);
        } else if (std.mem.startsWith(u8, line, "author ")) {
            current_author = line["author ".len..];
            if (current_group) |group| try commit_authors.put(group.commit, current_author.?);
        } else if (std.mem.startsWith(u8, line, "filename ")) {
            if (current_group) |group| {
                const author = current_author orelse "Unknown";
                const counts = countKindsRange(state.kinds, group.result_line, group.line_count);
                try addAuthorCountsLocked(ctx, state.ext, author, counts);
            }
            current_group = null;
            current_author = null;
        }
    }
}

fn runBlameWorker(ctx: *BlameContext, state: *const BlameFileState) void {
    const blame_opt = runGit(
        std.heap.page_allocator,
        &.{ "git", "blame", "--incremental", "--", state.path },
        256 * 1024 * 1024,
    ) catch {
        ctx.had_error.store(true, .monotonic);
        return;
    };
    const blame = blame_opt orelse return;
    defer std.heap.page_allocator.free(blame);

    parseBlameIncrementalOutput(ctx, state, blame) catch {
        ctx.had_error.store(true, .monotonic);
    };
}

fn blameJobCount(file_count: usize) usize {
    if (file_count <= 1) return 1;
    const cpus = std.Thread.getCpuCount() catch 1;
    return @max(1, @min(file_count, @min(cpus, 8)));
}

fn lessAuthorByExtTotalDesc(_: void, a: AuthorRow, b: AuthorRow) bool {
    if (!std.mem.eql(u8, a.ext, b.ext)) return std.mem.lessThan(u8, a.ext, b.ext);
    if (a.total() != b.total()) return a.total() > b.total();
    return std.mem.lessThan(u8, a.author, b.author);
}

fn collectTrackedFileSet(
    allocator: std.mem.Allocator,
) !?std.StringHashMap(void) {
    const tracked_opt = try runGit(allocator, &.{ "git", "ls-files" }, 128 * 1024 * 1024);
    const tracked = tracked_opt orelse return null;

    var set = std.StringHashMap(void).init(allocator);
    var it = std.mem.splitScalar(u8, tracked, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        try set.put(line, {});
    }
    return set;
}

fn collectLineAuthorRows(
    allocator: std.mem.Allocator,
    files: []const FileCount,
    count_opts: CountOptions,
) ![]AuthorRow {
    const tracked_set_opt = try collectTrackedFileSet(allocator);
    var tracked_set = tracked_set_opt orelse return &[_]AuthorRow{};

    var states: std.ArrayList(BlameFileState) = .empty;
    for (files) |file| {
        if (!tracked_set.contains(file.path)) continue;
        if (file.total() == 0) continue;
        const content = std.fs.cwd().readFileAlloc(allocator, file.path, 128 * 1024 * 1024) catch continue;
        const plugin = lang_plugins.resolve(file.ext);
        const force_test = lang_plugins.isTestPath(file.path, plugin);
        const kinds = try lang_plugins.classifyFileLines(allocator, content, force_test, plugin, count_opts);
        try states.append(allocator, .{
            .path = file.path,
            .ext = file.ext,
            .kinds = kinds,
        });
    }

    if (states.items.len == 0) return &[_]AuthorRow{};

    var ctx = BlameContext.init(allocator);
    if (states.items.len == 1) {
        runBlameWorker(&ctx, &states.items[0]);
    } else {
        var pool: std.Thread.Pool = undefined;
        try pool.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = blameJobCount(states.items.len),
        });
        defer pool.deinit();

        var wait_group: std.Thread.WaitGroup = .{};
        for (states.items) |*state| {
            pool.spawnWg(&wait_group, runBlameWorker, .{ &ctx, state });
        }
        wait_group.wait();
    }

    std.mem.sort(AuthorRow, ctx.rows.items, {}, lessAuthorByExtTotalDesc);
    const slice = try ctx.rows.toOwnedSlice(allocator);
    return slice;
}

fn addChurnRow(
    rows: *std.ArrayList(ChurnRow),
    index: *std.StringHashMap(usize),
    allocator: std.mem.Allocator,
    ext: []const u8,
    added: u64,
    deleted: u64,
) !void {
    if (index.get(ext)) |row_idx| {
        rows.items[row_idx].added += added;
        rows.items[row_idx].deleted += deleted;
        return;
    }
    try index.put(ext, rows.items.len);
    try rows.append(allocator, .{ .ext = ext, .added = added, .deleted = deleted });
}

fn parseChurnNumstatLine(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(ChurnRow),
    index: *std.StringHashMap(usize),
    matcher: *const ChurnExtMatcher,
    line: []const u8,
) !void {
    var fields = std.mem.splitScalar(u8, line, '\t');
    const added_s = fields.next() orelse return;
    const deleted_s = fields.next() orelse return;
    const path = fields.next() orelse return;
    if (added_s.len == 0 or deleted_s.len == 0) return;
    if (std.mem.eql(u8, added_s, "-") or std.mem.eql(u8, deleted_s, "-")) return;
    const ext = matcher.match(path) orelse return;
    const added = std.fmt.parseUnsigned(u64, added_s, 10) catch return;
    const deleted = std.fmt.parseUnsigned(u64, deleted_s, 10) catch return;
    try addChurnRow(rows, index, allocator, ext, added, deleted);
}

fn collectChurnRows(
    allocator: std.mem.Allocator,
    allowed: []const []const u8,
) !?[]ChurnRow {
    const matcher = try ChurnExtMatcher.init(allocator, allowed);
    const argv = &.{ "git", "log", "--all", "--no-merges", "--numstat", "--no-renames", "--format=" };
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return null;

    const stdout = child.stdout orelse {
        _ = child.kill() catch {};
        return null;
    };
    var reader_buf: [64 * 1024]u8 = undefined;
    var reader = stdout.readerStreaming(&reader_buf);

    var rows: std.ArrayList(ChurnRow) = .empty;
    var index = std.StringHashMap(usize).init(allocator);

    while (true) {
        const line_opt = reader.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => {
                const read_err = reader.err.?;
                _ = child.kill() catch {};
                return read_err;
            },
            error.StreamTooLong => {
                _ = child.kill() catch {};
                return null;
            },
        };
        const line = line_opt orelse break;
        try parseChurnNumstatLine(allocator, &rows, &index, &matcher, line);
    }

    const term = child.wait() catch return null;
    switch (term) {
        .Exited => |code| if (code != 0) return null,
        else => return null,
    }

    const slice = try rows.toOwnedSlice(allocator);
    return slice;
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

    const inside_git = isInsideGitRepo(allocator);
    var files_raw: std.ArrayList([]const u8) = .empty;
    if (inside_git) {
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

    var author_rows_opt: ?[]const AuthorRow = null;
    var author_note: ?[]const u8 = null;
    if (opts.line_authors) {
        if (!inside_git) {
            author_note = "line authors unavailable: not inside a git repository";
        } else {
            const author_rows = try collectLineAuthorRows(allocator, files.items, count_opts);
            if (author_rows.len == 0) {
                author_note = "line authors unavailable: git blame returned no tracked counted lines";
            } else {
                author_rows_opt = author_rows;
            }
        }
    }

    var churn_rows_opt: ?[]const ChurnRow = null;
    var churn_note: ?[]const u8 = null;
    if (opts.churn) {
        if (!inside_git) {
            churn_note = "churn unavailable: not inside a git repository";
        } else {
            if (try collectChurnRows(allocator, allowed.items)) |churn_rows| {
                if (churn_rows.len == 0) {
                    churn_note = "churn unavailable: no matching file types in commit history";
                } else {
                    churn_rows_opt = churn_rows;
                }
            } else {
                churn_note = "churn unavailable: git log returned no numstat data";
            }
        }
    }

    if (files.items.len == 0 and churn_rows_opt == null) {
        try w_noFiles(stdout, color);
        try stdout.flush();
        return;
    }

    if (!opts.summary and files.items.len > 0) {
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
        author_rows_opt,
        churn_rows_opt,
        total_code,
        total_test,
        total_comment,
        total_blank,
        opts.descending,
        render_opts,
        color,
    );

    if (author_note) |note| {
        try stdout.writeAll(color.dim);
        try stdout.print("{s}\n", .{note});
        try stdout.writeAll(color.reset);
    }

    if (churn_note) |note| {
        try stdout.writeAll(color.dim);
        try stdout.print("{s}\n", .{note});
        try stdout.writeAll(color.reset);
    }

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

test "parseArgs - git report flags" {
    const argv = [_][]const u8{ "sloc", "-lr" };
    const opts = try parseArgs(std.testing.allocator, &argv);
    try std.testing.expect(opts.line_authors);
    try std.testing.expect(opts.churn);
}
