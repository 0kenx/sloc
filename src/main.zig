const std = @import("std");

const default_exts = [_][]const u8{
    "c",     "cpp",   "h",     "hpp",   "cmake",  "mk",   "bzl",  "py",
    "ipynb", "js",    "jsx",   "ts",    "svelte", "css",  "htm",  "html",
    "htmx",  "xhtml", "go",    "java",  "hs",     "fut",  "sol",  "move",
    "mo",    "rs",    "zig",   "sh",    "nix",    "tf",   "lua",  "yml",
    "json",  "proto", "gql",   "sql",
};

const test_path_dirs = [_][]const u8{
    "test",    "tests",      "spec",       "specs",   "__tests__",
    "e2e",     "cypress",    "playwright", "testing", "fixtures",
};

const jvm_exts = [_][]const u8{ "java", "kt", "scala", "groovy" };
const jvm_test_suffixes = [_][]const u8{ "Test", "Tests", "IT", "ITCase" };
const filename_test_suffixes = [_][]const u8{ "_test", "_tests", "_spec" };

const FileCount = struct {
    path: []const u8,
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
    try w.writeAll(
        \\Usage: sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-h]
        \\Count lines of code and tests, excluding blanks, bracket-only lines, and comments.
        \\
        \\Options:
        \\  -a, --add ext1,ext2     Include additional file extensions
        \\  -e, --exclude ext1,ext2 Exclude specified file extensions
        \\  -o, --only ext1,ext2    Include ONLY the specified extensions (overrides -a and -e)
        \\  -d, --descending        Display results in descending order by line count
        \\  -s, --summary           Summary mode - only show totals
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

fn splitCommaAppend(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    spec: []const u8,
) !void {
    var it = std.mem.splitScalar(u8, spec, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        try out.append(allocator, trimmed);
    }
}

fn hasExt(list: []const []const u8, ext: []const u8) bool {
    for (list) |e| if (std.mem.eql(u8, e, ext)) return true;
    return false;
}

fn fileExtension(path: []const u8) ?[]const u8 {
    const base = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return null;
    if (dot == 0 or dot + 1 == base.len) return null;
    return base[dot + 1 ..];
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
                if (std.mem.eql(u8, comp, td)) return true;
            }
        }
    }

    const base = parts_buf[n - 1];

    if (std.mem.eql(u8, base, "conftest.py")) return true;

    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return false;
    if (dot == 0) return false;
    const name = base[0..dot];
    const ext = base[dot + 1 ..];
    if (ext.len == 0) return false;

    if (std.mem.startsWith(u8, name, "test_") and name.len > 5) return true;
    if (std.mem.startsWith(u8, name, "tests_") and name.len > 6) return true;

    for (filename_test_suffixes) |s| {
        if (name.len > s.len and std.mem.endsWith(u8, name, s)) return true;
    }

    if (std.mem.lastIndexOfScalar(u8, name, '.')) |inner| {
        const inner_ext = name[inner + 1 ..];
        if (std.mem.eql(u8, inner_ext, "test") or std.mem.eql(u8, inner_ext, "spec")) return true;
    }

    var is_jvm = false;
    for (jvm_exts) |je| if (std.mem.eql(u8, ext, je)) {
        is_jvm = true;
        break;
    };
    if (is_jvm) {
        for (jvm_test_suffixes) |s| {
            if (name.len > s.len and std.mem.endsWith(u8, name, s)) return true;
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
    const ext = fileExtension(path) orelse return false;
    return hasExt(allowed, ext);
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
                if (std.mem.eql(u8, e, x)) continue :outer;
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
        const ext = fileExtension(f.path) orelse continue;
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

fn indent(w: *std.Io.Writer, depth: usize) !void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try w.writeAll("│   ");
}

fn pathDirname(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| return path[0..idx];
    return ".";
}

fn lessByTotalDesc(_: void, a: FileCount, b: FileCount) bool {
    return a.total() > b.total();
}

fn lessByPath(_: void, a: FileCount, b: FileCount) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn countPathDepth(path: []const u8) usize {
    var depth: usize = 0;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |_| depth += 1;
    return depth;
}

fn dirTotals(files: []const FileCount, prefix: []const u8) struct { c: u64, t: u64 } {
    var c: u64 = 0;
    var t: u64 = 0;
    for (files) |f| {
        if (f.path.len > prefix.len and std.mem.startsWith(u8, f.path, prefix) and f.path[prefix.len] == '/') {
            c += f.code_count;
            t += f.test_count;
        }
    }
    return .{ .c = c, .t = t };
}

fn writePadded(w: *std.Io.Writer, v: u64, width: usize) !void {
    const d = digitsU64(v);
    var pad = if (width > d) width - d else 0;
    while (pad > 0) : (pad -= 1) try w.writeByte(' ');
    try w.print("{d}", .{v});
}

fn writePaddedStr(w: *std.Io.Writer, s: []const u8, width: usize) !void {
    var pad = if (width > s.len) width - s.len else 0;
    while (pad > 0) : (pad -= 1) try w.writeByte(' ');
    try w.writeAll(s);
}

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

    const allowed = try buildAllowedExts(allocator, &opts);

    try stdout.writeAll("Included extensions: ");
    for (allowed.items, 0..) |e, i| {
        if (i > 0) try stdout.writeAll(", ");
        try stdout.writeAll(e);
    }
    try stdout.writeByte('\n');

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
        const is_rust = blk: {
            const ext = fileExtension(path) orelse break :blk false;
            break :blk std.mem.eql(u8, ext, "rs");
        };
        const c = countFile(content, force_test, is_rust);
        total_code += c.code_count;
        total_test += c.test_count;
        try files.append(allocator, .{
            .path = path,
            .test_count = c.test_count,
            .code_count = c.code_count,
        });
    }

    const total_sloc = total_code + total_test;

    if (opts.summary) {
        try stdout.print("Total SLOC: {d}  (code: {d}, test: {d})\n", .{ total_sloc, total_code, total_test });
    } else {
        var max_c: usize = @max(digitsU64(total_code), 5);
        var max_t: usize = @max(digitsU64(total_test), 5);
        for (files.items) |f| {
            max_c = @max(max_c, digitsU64(f.code_count));
            max_t = @max(max_t, digitsU64(f.test_count));
        }

        try writePaddedStr(stdout, "code", max_c);
        try stdout.writeAll("  ");
        try writePaddedStr(stdout, "test", max_t);
        try stdout.writeAll("  path\n");

        if (opts.descending) {
            const sorted = try allocator.alloc(FileCount, files.items.len);
            @memcpy(sorted, files.items);
            std.mem.sort(FileCount, sorted, {}, lessByTotalDesc);
            for (sorted) |f| {
                try writePadded(stdout, f.code_count, max_c);
                try stdout.writeAll("  ");
                try writePadded(stdout, f.test_count, max_t);
                try stdout.writeAll("  ");
                try stdout.writeAll(f.path);
                try stdout.writeByte('\n');
            }
        } else {
            const sorted = try allocator.alloc(FileCount, files.items.len);
            @memcpy(sorted, files.items);
            std.mem.sort(FileCount, sorted, {}, lessByPath);

            try writePadded(stdout, total_code, max_c);
            try stdout.writeAll("  ");
            try writePadded(stdout, total_test, max_t);
            try stdout.writeAll("  .\n");

            var printed = std.StringHashMap(void).init(allocator);

            for (sorted) |f| {
                const dir = pathDirname(f.path);
                const basename = std.fs.path.basename(f.path);

                var depth: usize = 0;
                if (!std.mem.eql(u8, dir, ".")) {
                    depth = countPathDepth(dir);
                }

                if (!std.mem.eql(u8, dir, ".")) {
                    var idx: usize = 0;
                    while (idx <= dir.len) {
                        const next_slash = std.mem.indexOfScalarPos(u8, dir, idx, '/');
                        const end = next_slash orelse dir.len;
                        if (end == idx) {
                            if (next_slash == null) break;
                            idx = end + 1;
                            continue;
                        }
                        const current_dir = dir[0..end];
                        if (!printed.contains(current_dir)) {
                            const totals = dirTotals(sorted, current_dir);
                            const this_depth = std.mem.count(u8, current_dir, "/");
                            const dir_name = std.fs.path.basename(current_dir);
                            try writePadded(stdout, totals.c, max_c);
                            try stdout.writeAll("  ");
                            try writePadded(stdout, totals.t, max_t);
                            try stdout.writeAll("  ");
                            try indent(stdout, this_depth);
                            try stdout.print("├──{s}/\n", .{dir_name});
                            const key = try allocator.dupe(u8, current_dir);
                            try printed.put(key, {});
                        }
                        if (next_slash == null) break;
                        idx = end + 1;
                    }
                }

                try writePadded(stdout, f.code_count, max_c);
                try stdout.writeAll("  ");
                try writePadded(stdout, f.test_count, max_t);
                try stdout.writeAll("  ");
                try indent(stdout, depth);
                try stdout.print("├──{s}\n", .{basename});
            }
        }
    }

    if (files.items.len > 0) {
        try stdout.writeByte('\n');
        try stdout.writeAll("Summary by file type:\n");

        const exts = try uniqExtensions(allocator, files.items);

        const ExtRow = struct {
            ext: []const u8,
            code: u64,
            test_c: u64,
        };

        const rows = try allocator.alloc(ExtRow, exts.items.len);
        for (exts.items, 0..) |e, i| {
            var ec: u64 = 0;
            var et: u64 = 0;
            for (files.items) |f| {
                const fe = fileExtension(f.path) orelse continue;
                if (!std.mem.eql(u8, fe, e)) continue;
                ec += f.code_count;
                et += f.test_count;
            }
            rows[i] = .{ .ext = e, .code = ec, .test_c = et };
        }

        if (opts.descending) {
            std.mem.sort(ExtRow, rows, {}, struct {
                fn lt(_: void, a: ExtRow, b: ExtRow) bool {
                    return (a.code + a.test_c) > (b.code + b.test_c);
                }
            }.lt);
        } else {
            std.mem.sort(ExtRow, rows, {}, struct {
                fn lt(_: void, a: ExtRow, b: ExtRow) bool {
                    return std.mem.lessThan(u8, a.ext, b.ext);
                }
            }.lt);
        }

        for (rows) |r| {
            try writePadded(stdout, r.code, 6);
            try stdout.writeAll("  ");
            try writePadded(stdout, r.test_c, 6);
            try stdout.writeAll("  .");
            try stdout.writeAll(r.ext);
            try stdout.writeByte('\n');
        }
        try stdout.writeByte('\n');
        try writePadded(stdout, total_code, 6);
        try stdout.writeAll("  ");
        try writePadded(stdout, total_test, 6);
        try stdout.writeAll("  TOTAL (code / test)\n");
    }

    try stdout.flush();
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
    try std.testing.expect(isTestPath("FooIT.scala"));
    try std.testing.expect(!isTestPath("FooTest.py"));
    try std.testing.expect(!isTestPath("main.go"));
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
