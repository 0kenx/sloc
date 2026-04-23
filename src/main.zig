const std = @import("std");
const build_options = @import("build_options");

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

const test_path_dirs = [_][]const u8{
    "test", "tests",   "spec",       "specs",   "__tests__",
    "e2e",  "cypress", "playwright", "testing", "fixtures",
};

const jvm_exts = [_][]const u8{ "java", "kt", "scala", "groovy" };
const jvm_test_suffixes = [_][]const u8{ "Test", "Tests", "IT", "ITCase" };
const filename_test_suffixes = [_][]const u8{ "_test", "_tests", "_spec" };

const FileCount = struct {
    path: []const u8,
    ext: []const u8,
    test_count: u64,
    code_count: u64,

    fn total(self: FileCount) u64 {
        return self.test_count + self.code_count;
    }
};

const Options = struct {
    add: std.ArrayList([]const u8) = .empty,
    exclude: std.ArrayList([]const u8) = .empty,
    only: std.ArrayList([]const u8) = .empty,
    descending: bool = false,
    summary: bool = false,
    version: bool = false,
    help: bool = false,
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
        } else if (std.mem.eql(u8, a, "-V") or std.mem.eql(u8, a, "--version")) {
            opts.version = true;
        } else if (try takeValueArg(argv, &i, a, "-a", "--add")) |v| {
            try opts.add.append(allocator, v);
        } else if (try takeValueArg(argv, &i, a, "-e", "--exclude")) |v| {
            try opts.exclude.append(allocator, v);
        } else if (try takeValueArg(argv, &i, a, "-o", "--only")) |v| {
            try opts.only.append(allocator, v);
        } else {
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

fn printHelp(w: *std.Io.Writer) !void {
    try w.print("sloc {s}\n\n", .{build_options.version});
    try w.writeAll(
        \\Usage: sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-V] [-h]
        \\Count lines of code and tests, excluding blanks, bracket-only lines, and comments.
        \\
        \\Options:
        \\  -a, --add ext1,ext2     Include additional file extensions
        \\  -e, --exclude ext1,ext2 Exclude specified file extensions
        \\  -o, --only ext1,ext2    Include ONLY the specified extensions (overrides -a and -e)
        \\  -d, --descending        Display results in descending order by line count
        \\  -s, --summary           Summary mode - only show totals
        \\  -V, --version           Display version information
        \\  -h, --help              Display this help message
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

fn hasExt(list: []const []const u8, ext: []const u8) bool {
    for (list) |e| if (asciiEqlIgnoreCase(e, ext)) return true;
    return false;
}

fn fileExtension(path: []const u8) ?[]const u8 {
    const base = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return null;
    if (dot == 0 or dot + 1 == base.len) return null;
    return base[dot + 1 ..];
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

fn isTestPath(path: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, '/');
    var parts_buf: [256][]const u8 = undefined;
    var n: usize = 0;
    while (it.next()) |p| {
        if (n >= parts_buf.len) break;
        parts_buf[n] = p;
        n += 1;
    }
    if (n == 0) return false;

    if (n >= 2) {
        for (parts_buf[0 .. n - 1]) |comp| {
            for (test_path_dirs) |td| {
                if (asciiEqlIgnoreCase(comp, td)) return true;
            }
        }
    }

    const base = parts_buf[n - 1];

    if (asciiEqlIgnoreCase(base, "conftest.py")) return true;

    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return false;
    if (dot == 0) return false;
    const name = base[0..dot];
    const ext = base[dot + 1 ..];
    if (ext.len == 0) return false;

    if (asciiStartsWithIgnoreCase(name, "test_") and name.len > 5) return true;
    if (asciiStartsWithIgnoreCase(name, "tests_") and name.len > 6) return true;

    for (filename_test_suffixes) |s| {
        if (name.len > s.len and asciiEndsWithIgnoreCase(name, s)) return true;
    }

    if (std.mem.lastIndexOfScalar(u8, name, '.')) |inner| {
        const inner_ext = name[inner + 1 ..];
        if (asciiEqlIgnoreCase(inner_ext, "test") or asciiEqlIgnoreCase(inner_ext, "spec")) return true;
    }

    var is_jvm = false;
    for (jvm_exts) |je| if (asciiEqlIgnoreCase(ext, je)) {
        is_jvm = true;
        break;
    };
    if (is_jvm) {
        for (jvm_test_suffixes) |s| {
            if (name.len > s.len and asciiEndsWithIgnoreCase(name, s)) return true;
        }
    }

    return false;
}

fn isWhitespaceByte(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r';
}

fn isSkippedLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0) return true;

    var all_brackets = true;
    for (trimmed) |c| {
        switch (c) {
            '{', '}', '[', ']', '(', ')' => {},
            else => {
                all_brackets = false;
                break;
            },
        }
    }
    if (all_brackets) return true;

    if (trimmed.len >= 2 and trimmed[0] == '/' and trimmed[1] == '/') return true;
    if (trimmed.len >= 2 and trimmed[0] == '-' and trimmed[1] == '-') return true;
    if (trimmed[0] == '#') return true;
    if (trimmed[0] == '\'') return true;

    return false;
}

fn isCfgContinuation(line: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, " \t\r");
    if (trimmed.len == 0) return true;
    if (std.mem.startsWith(u8, trimmed, "#[")) return true;
    if (std.mem.startsWith(u8, trimmed, "mod")) {
        if (trimmed.len == 3) return true;
        if (isWhitespaceByte(trimmed[3])) return true;
    }
    return false;
}

fn containsTestModDecl(line: []const u8) bool {
    var i: usize = 0;
    while (i + 3 <= line.len) : (i += 1) {
        if (i > 0) {
            const prev = line[i - 1];
            if (!isWhitespaceByte(prev)) continue;
        }
        if (line[i] != 'm' or line[i + 1] != 'o' or line[i + 2] != 'd') continue;
        var j = i + 3;
        if (j >= line.len) return false;
        if (!isWhitespaceByte(line[j])) continue;
        while (j < line.len and isWhitespaceByte(line[j])) : (j += 1) {}
        if (j >= line.len) return false;
        const first = line[j];
        const is_ident_start = (first == '_') or std.ascii.isAlphabetic(first);
        if (!is_ident_start) continue;
        j += 1;
        while (j < line.len) : (j += 1) {
            const c = line[j];
            if (!(c == '_' or std.ascii.isAlphanumeric(c))) break;
        }
        while (j < line.len and isWhitespaceByte(line[j])) : (j += 1) {}
        if (j < line.len and line[j] == '{') return true;
    }
    return false;
}

const LineCount = struct { test_count: u64, code_count: u64 };

fn countFile(content: []const u8, force_test: bool, rust_mode: bool) LineCount {
    var tc: u64 = 0;
    var cc: u64 = 0;
    var in_test = false;
    var depth: i64 = 0;
    var seen_cfg = false;

    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw_line| {
        var line = raw_line;
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

        if (rust_mode and !force_test) {
            if (std.mem.indexOf(u8, line, "#[cfg(test)]") != null) {
                seen_cfg = true;
            }
            if (seen_cfg and containsTestModDecl(line)) {
                in_test = true;
                seen_cfg = false;
            }
            if (in_test) {
                for (line) |c| {
                    if (c == '{') {
                        depth += 1;
                    } else if (c == '}') {
                        depth -= 1;
                    }
                }
            }
            if (seen_cfg and !isCfgContinuation(line)) {
                seen_cfg = false;
            }
        }

        if (!isSkippedLine(line)) {
            if (force_test or in_test) tc += 1 else cc += 1;
        }

        if (in_test and depth <= 0) {
            in_test = false;
            depth = 0;
        }
    }

    return .{ .test_count = tc, .code_count = cc };
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

// ---------- tree ----------

const Node = struct {
    name: []const u8,
    is_dir: bool,
    code: u64,
    test_c: u64,
    children: std.ArrayList(*Node),

    fn total(self: *const Node) u64 {
        return self.code + self.test_c;
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

        var cursor = root;
        var it = std.mem.splitScalar(u8, f.path, '/');
        var part_opt = it.next();
        while (part_opt) |part| {
            const next = it.next();
            const is_file = (next == null);
            const node = try getOrCreateChild(allocator, cursor, part, !is_file);
            node.code += f.code_count;
            node.test_c += f.test_count;
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
    max_c: usize,
    max_t: usize,
    color: Color,
) !void {
    try writeCodeNum(w, node.code, max_c, color);
    try w.writeAll("  ");
    try writeTestNum(w, node.test_c, max_t, color);
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
        try printTree(w, allocator, child, new_prefix, child_last, false, max_c, max_t, color);
    }
}

// ---------- summary ----------

const ExtRow = struct {
    ext: []const u8,
    code: u64,
    test_c: u64,

    fn total(self: ExtRow) u64 {
        return self.code + self.test_c;
    }
};

fn printExtensionTable(
    w: *std.Io.Writer,
    allocator: std.mem.Allocator,
    files: []const FileCount,
    total_code: u64,
    total_test: u64,
    descending: bool,
    color: Color,
) !void {
    const exts = try uniqExtensions(allocator, files);
    const rows = try allocator.alloc(ExtRow, exts.items.len);
    for (exts.items, 0..) |e, i| {
        var ec: u64 = 0;
        var et: u64 = 0;
        for (files) |f| {
            if (!asciiEqlIgnoreCase(f.ext, e)) continue;
            ec += f.code_count;
            et += f.test_count;
        }
        rows[i] = .{ .ext = e, .code = ec, .test_c = et };
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

    var max_c: usize = @max(commaWidth(total_code), 4);
    var max_t: usize = @max(commaWidth(total_test), 4);
    var max_ext: usize = 4; // "TYPE"
    for (rows) |r| {
        max_c = @max(max_c, commaWidth(r.code));
        max_t = @max(max_t, commaWidth(r.test_c));
        max_ext = @max(max_ext, r.ext.len + 1); // +1 for leading '.'
    }
    const bar_width: usize = 20;

    var max_total: u64 = 0;
    for (rows) |r| max_total = @max(max_total, r.total());

    // Header row
    try writeRightHeader(w, "CODE", max_c, color);
    try w.writeAll("  ");
    try writeRightHeader(w, "TEST", max_t, color);
    try w.writeAll("  ");
    try writeLeftHeader(w, "TYPE", color);
    try w.writeByte('\n');

    const header_rule_width = max_c + 2 + max_t + 2 + max_ext + 1 + bar_width;
    try writeRule(w, header_rule_width, color);

    for (rows) |r| {
        try writeCodeNum(w, r.code, max_c, color);
        try w.writeAll("  ");
        try writeTestNum(w, r.test_c, max_t, color);
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

    try writeRule(w, max_c + 2 + max_t, color);

    try w.writeAll(color.bold);
    try writePlainPadded(w, total_code, max_c);
    try w.writeAll("  ");
    try writePlainPadded(w, total_test, max_t);
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

    for (files_raw.items) |path| {
        const content = std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024 * 1024) catch continue;
        const force_test = isTestPath(path);
        const matched_ext = matchedAllowedExt(path, allowed.items) orelse continue;
        const is_rust = blk: {
            break :blk asciiEqlIgnoreCase(matched_ext, "rs");
        };
        const c = countFile(content, force_test, is_rust);
        total_code += c.code_count;
        total_test += c.test_count;
        try files.append(allocator, .{
            .path = path,
            .ext = matched_ext,
            .test_count = c.test_count,
            .code_count = c.code_count,
        });
    }

    if (files.items.len == 0) {
        try w_noFiles(stdout, color);
        try stdout.flush();
        return;
    }

    if (!opts.summary) {
        var max_c: usize = @max(commaWidth(total_code), 4);
        var max_t: usize = @max(commaWidth(total_test), 4);
        for (files.items) |f| {
            max_c = @max(max_c, commaWidth(f.code_count));
            max_t = @max(max_t, commaWidth(f.test_count));
        }

        try writeRightHeader(stdout, "CODE", max_c, color);
        try stdout.writeAll("  ");
        try writeRightHeader(stdout, "TEST", max_t, color);
        try stdout.writeAll("  ");
        try writeLeftHeader(stdout, "PATH", color);
        try stdout.writeByte('\n');
        try writeRule(stdout, max_c + 2 + max_t + 2 + 32, color);

        if (opts.descending) {
            try writeCodeNum(stdout, total_code, max_c, color);
            try stdout.writeAll("  ");
            try writeTestNum(stdout, total_test, max_t, color);
            try stdout.writeAll("  ");
            try stdout.writeAll(color.bold);
            try stdout.writeAll(".");
            try stdout.writeAll(color.reset);
            try stdout.writeByte('\n');

            const sorted = try allocator.alloc(FileCount, files.items.len);
            @memcpy(sorted, files.items);
            std.mem.sort(FileCount, sorted, {}, lessByTotalDesc);
            for (sorted) |f| {
                try writeCodeNum(stdout, f.code_count, max_c, color);
                try stdout.writeAll("  ");
                try writeTestNum(stdout, f.test_count, max_t, color);
                try stdout.writeAll("  ");
                if (isTestPath(f.path)) {
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
            try printTree(stdout, allocator, root, "", false, true, max_c, max_t, color);
        }
        try stdout.writeByte('\n');
    }

    try printExtensionTable(
        stdout,
        allocator,
        files.items,
        total_code,
        total_test,
        opts.descending,
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

test "isTestPath - path components" {
    try std.testing.expect(isTestPath("src/tests/foo.py"));
    try std.testing.expect(isTestPath("tests/foo.py"));
    try std.testing.expect(isTestPath("a/b/spec/foo.js"));
    try std.testing.expect(isTestPath("e2e/login.ts"));
    try std.testing.expect(!isTestPath("src/main.py"));
}

test "isTestPath - filename patterns" {
    try std.testing.expect(isTestPath("foo_test.go"));
    try std.testing.expect(isTestPath("bar_spec.rb"));
    try std.testing.expect(isTestPath("foo.test.ts"));
    try std.testing.expect(isTestPath("a/foo.spec.ts"));
    try std.testing.expect(isTestPath("test_foo.py"));
    try std.testing.expect(isTestPath("conftest.py"));
    try std.testing.expect(isTestPath("FooTest.java"));
    try std.testing.expect(isTestPath("FooTests.JAVA"));
    try std.testing.expect(isTestPath("FooIT.scala"));
    try std.testing.expect(!isTestPath("FooTest.py"));
    try std.testing.expect(!isTestPath("main.go"));
}

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

test "isSkippedLine" {
    try std.testing.expect(isSkippedLine(""));
    try std.testing.expect(isSkippedLine("   "));
    try std.testing.expect(isSkippedLine("  { "));
    try std.testing.expect(isSkippedLine("})"));
    try std.testing.expect(isSkippedLine("// comment"));
    try std.testing.expect(isSkippedLine("  -- haskell comment"));
    try std.testing.expect(isSkippedLine("# python"));
    try std.testing.expect(isSkippedLine("' fish"));
    try std.testing.expect(!isSkippedLine("let x = 1;"));
    try std.testing.expect(!isSkippedLine("function foo() {"));
}

test "countFile - basic" {
    const src =
        \\// comment
        \\let x = 1;
        \\
        \\{
        \\let y = 2;
        \\}
    ;
    const r = countFile(src, false, false);
    try std.testing.expectEqual(@as(u64, 0), r.test_count);
    try std.testing.expectEqual(@as(u64, 2), r.code_count);
}

test "countFile - rust cfg test" {
    const src =
        \\fn real() { 1 }
        \\
        \\#[cfg(test)]
        \\mod tests {
        \\    fn t1() {}
        \\    fn t2() {}
        \\}
        \\
        \\fn more() { 2 }
    ;
    const r = countFile(src, false, true);
    try std.testing.expect(r.code_count >= 2);
    try std.testing.expect(r.test_count >= 2);
}

test "countFile - force_test" {
    const src = "let x = 1;\nlet y = 2;\n";
    const r = countFile(src, true, false);
    try std.testing.expectEqual(@as(u64, 2), r.test_count);
    try std.testing.expectEqual(@as(u64, 0), r.code_count);
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
