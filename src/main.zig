const std = @import("std");
const heap = std.heap;
const io = std.io;
const log = std.log;
const os = std.os;
const posix = std.posix;
const process = std.process;

const cova = @import("cova");
const cli = @import("cli.zig");

const art = @import("art.zig");
const nl = @import("nl.zig");

pub fn main() !void {
    const stdout_file = io.getStdOut().writer();
    var stdout_bw = io.bufferedWriter(stdout_file);
    defer stdout_bw.flush() catch log.warn("Couldn't flush stdout before exiting!", .{});
    const stdout = stdout_bw.writer().any();

    if (os.linux.getuid() != 0) {
        try stdout_file.print("{s}\n\n                          DisCo must be run as sudo!\n", .{ art.sudo });
        return;
    }

    var gpa = heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer if (gpa.detectLeaks()) log.err("Memory leak detected!", .{});
    const alloc = gpa.allocator();


    // Parse Args
    var main_cmd = try cli.setup_cmd.init(alloc, .{});
    defer main_cmd.deinit();
    var args_iter = try cova.ArgIteratorGeneric.init(alloc);
    defer args_iter.deinit();
    cova.parseArgs(
        &args_iter,
        cli.CommandT,
        main_cmd,
        stdout,
        .{},
    ) catch |err| {
        try stdout_bw.flush();
        switch (err) {
            error.UsageHelpCalled => return,
            error.TooManyValues,
            error.UnrecognizedArgument,
            error.UnexpectedArgument,
            error.CouldNotParseOption => {},
            else => |parse_err| return parse_err,
        }
    };

    //const main_opts = try main_cmd.getOpts(.{});
    const main_vals = try main_cmd.getVals(.{});

    // Interface Name
    const if_name = try (main_vals.get("interface").?).getAs([]const u8);
    const if_idx = nl.getIfIdx(if_name) catch |err| switch (err) {
        error.NoInterfaceFound => {
            log.err("Netlink request timed out. Could not find the '{s}' interface.", .{ if_name });
            return;
        },
        else => return err,
    };

    // Single Use
    if (main_cmd.matchSubCmd("change")) |change_cmd| {
        const change_opts = try change_cmd.getOpts(.{});
        if (change_opts.get("mac")) |mac_opt| {
            try stdout_file.print("Changing the MAC for {s}...\n", .{ if_name });
            const new_mac = try mac_opt.val.getAs([6]u8);
            nl.changeMAC(if_idx, new_mac) catch |err| switch (err) {
                error.BUSY => {
                    log.err("The interface '{s}' is busy so the MAC could not be changed.", .{ if_name });
                    return;
                },
                else => {
                    log.err("Netlink request error. The MAC for interface '{s}' could not be changed.", .{ if_name });
                    return;
                },
            };
            try stdout_file.print("Changed the MAC for {s} to {X}\n", .{ if_name, new_mac });
        }
    }
}
