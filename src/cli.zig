//! Cova Commands for the DisCo CLI.

const builtin = @import("builtin");
const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const json = std.json;
const log = std.log;
const mem = std.mem;
const meta = std.meta;
const net = std.net;
const testing = std.testing;
const time = std.time;

const cova = @import("cova");
const nl = @import("netlink.zig");
const netdata = @import("netdata.zig");
const address = netdata.address;
const oui = netdata.oui;
const proto = @import("protocols.zig");
const serve = proto.serve;
const wpa = proto.wpa;

/// The Cova Command Type for DisCo.
pub const CommandT = cova.Command.Custom(.{
    .global_help_prefix = "DisCo",
    .help_category_order = &.{ .Prefix, .Usage, .Header, .Aliases, .Examples, .Values, .Options, .Commands },
    .allow_abbreviated_cmds = true,
    .abbreviated_min_len = 1,
    .val_config = .{
        .custom_types = &.{
            net.Address,
            fs.File,
            fs.Dir,
            [6]u8,
            [4]u8,
            [3]u8,
            address.IPv4,
            address.RandomMACKind,
            nl.route.IFF,
            nl._80211.IFTYPE,
            nl._80211.CHANNEL_WIDTH,
            wpa.Protocol,
        },
        .child_type_parse_fns = &.{
            .{
                .ChildT = net.Address,
                .parse_fn = struct{
                    pub fn parseIP(addr: []const u8, _: mem.Allocator) !net.Address {
                        var iter = mem.splitScalar(u8, addr, ':');
                        return net.Address.parseIp(
                            iter.first(),
                            try fmt.parseInt(u16, iter.next() orelse "-", 10)
                        ) catch |err| {
                            log.err("The provided destination address '{s}' is invalid.", .{ addr });
                            return err;
                        };
                    }
                }.parseIP,
            },
            .{
                .ChildT = fs.File,
                .parse_fn = struct{
                    pub fn parseFilePath(path: []const u8, _: mem.Allocator) !fs.File {
                        var cwd = fs.cwd();
                        return cwd.openFile(path, .{ .lock = .shared }) catch |err| {
                            log.err("The provided path to the File '{s}' is invalid.", .{ path });
                            return err;
                        };
                    }
                }.parseFilePath,
            },
            .{
                .ChildT = fs.Dir,
                .parse_fn = struct{
                    pub fn parseDirPath(path: []const u8, _: mem.Allocator) !fs.Dir {
                        var cwd = fs.cwd();
                        return cwd.openDir(path, .{ .iterate = true }) catch |err| {
                            log.err("The provided path to the Dir '{s}' is invalid.", .{ path });
                            return err;
                        };
                    }
                }.parseDirPath,
            },
        },
        .child_type_aliases = &.{
            .{ .ChildT = bool, .alias = "toggle" },
            .{ .ChildT = []const u8, .alias = "text" },
            .{ .ChildT = usize, .alias = "positive_number" },
            .{ .ChildT = fs.File, .alias = "filepath" },
            .{ .ChildT = fs.Dir, .alias = "directory" },
            .{ .ChildT = net.Address, .alias = "ip_address:port" },
            .{ .ChildT = [6]u8, .alias = "mac_address" },
            .{ .ChildT = [4]u8, .alias = "ip_address" },
            .{ .ChildT = [3]u8, .alias = "oui" },
            .{ .ChildT = address.IPv4, .alias = "ip_address/cidr" },
            .{ .ChildT = nl.route.IFF, .alias = "interface_state" },
            .{ .ChildT = nl._80211.CHANNEL_WIDTH, .alias = "channel_width" },
            .{ .ChildT = wpa.Protocol, .alias = "security_protocol" },
        },
    }
});
const OptionT = CommandT.OptionT;
const ValueT = CommandT.ValueT;

/// The Root Setup Command for DisCo
pub const setup_cmd = CommandT{
    .name = "disco",
    .description = "Discreetly Connect to networks.",
    .examples = &.{
        "disco wlan0",
        "disco wlan0 set --mac 00:11:22:aa:bb:cc",
        "disco wlan0 add --ip 192.168.10.10",
        "disco wlan0 del --route 192.168.0.0/16",
        "disco sys set --hostname 'shaggy'",
        "disco host --dir '/tmp'",
    },
    .cmd_groups = &.{ "ACTIVE", "INTERFACE", "SETTINGS" },
    .sub_cmds_mandatory = false,
    .vals_mandatory = false,
    .vals = &.{
        // TODO replace this w/ the `--interface` Option?
        ValueT.ofType([]const u8, .{
            .name = "interface",
            .description = "The Network Interface to use. (This is mandatory)"
        }),
    },
    .opts = &.{
        .{
            .name = "interfaces",
            .description = "The WiFi Interface(s) available for DisCo to use. (Multiple Interfaces can be provided.)",
            .short_name = 'i',
            .long_name = "interfaces",
            .val = ValueT.ofType([]const u8, .{
                .set_behavior = .Multi,
                .max_entries = 32,
            }),
        },
        // TODO Implement these Base Options
        .{
            .name = "log-path",
            .description = "Save the JSON output to the specified Log Path.",
            .short_name = 'l',
            .long_name = "log-path",
            .val = ValueT.ofType(fs.File, .{
                .name = "log_path",
                .description = "Path to the save JSON Log File.",
            }),
        },
        .{
            .name = "no-tui",
            .description = "Run DisCo without a TUI.",
            .short_name = 'n',
            .long_name = "no-tui",
        },
        .{
            .name = "no-mouse",
            .description = "Disable mouse events for the TUI.",
            .long_name = "no-mouse",
        },
    },
    .sub_cmds = &.{
        .{
            .name = "connect",
            .description = "Connect to a WiFi Network using the specified Interface.",
            .cmd_group = "ACTIVE",
            .vals = &.{
                ValueT.ofType([]const u8, .{
                    .name = "ssid",
                    .description = "Set the SSID of the Network. (Up to 32 characters)",
                    .valid_fn = struct {
                        pub fn validPass(arg: []const u8, _: mem.Allocator) bool {
                            return arg.len > 0 and arg.len <= 32;
                        }
                    }.validPass,
                }),
            },
            .opts = &.{
                channels_opt,
                .{
                    .name = "passphrase",
                    .description = "Set the Passhprase for the Network. (Between 8-63 characters)",
                    .long_name = "passphrase",
                    .alias_long_names = &.{ "password", "pwd" },
                    .short_name = 'p',
                    .val = ValueT.ofType([]const u8, .{
                        .valid_fn = struct {
                            pub fn validPass(arg: []const u8, _: mem.Allocator) bool {
                                return arg.len >= 8 and arg.len <= 63;
                            }
                        }.validPass,
                    }),
                },
                .{
                    .name = "security",
                    .description = "Set the WiFi Secruity Protocol. (open, wep, or wpa2 | Default = wpa2)",
                    .long_name = "security",
                    .short_name = 's',
                    .val = ValueT.ofType(wpa.Protocol, .{ .default_val = .wpa2 }),
                },
                .{
                    .name = "dhcp",
                    .description = "Obtain an IP Address via DHCP upon successful connection.",
                    .long_name = "dhcp",
                    .short_name = 'd',
                },
                .{
                    .name = "gateway",
                    .description = "Automatically set the Gateway after obtaining an IP Address.",
                    .long_name = "gateway",
                    .alias_long_names = &.{ "gw" },
                    .short_name = 'g',
                },
            },
        },
        .{
            .name = "serve",
            .alias_names = &.{ "host" },
            .description = "Serve files from the provided `--directory` on the designated `--port` using HTTP and TFTP.",
            .cmd_group = "ACTIVE",
            .opts = &.{
                .{
                    .name = "port",
                    .description = "Port to serve on. (Default: 12070)",
                    .long_name = "port",
                    .short_name = 'p',
                    .val = ValueT.ofType(u16, .{ .default_val = 12070 }),
                },
                .{
                    .name = "directory",
                    .description = "Directory to serve. (Default: Current Directory '.')",
                    .long_name = "directory",
                    .short_name = 'd',
                    .val = ValueT.ofType([]const u8, .{
                        .default_val = ".",
                        .alias_child_type= "path",
                        .valid_fn = struct{
                            pub fn validatePath(path: []const u8, _: mem.Allocator) bool {
                                var dir = fs.openDirAbsolute(path, .{}) catch return false;
                                defer dir.close();
                                return true;
                            }
                        }.validatePath,
                    }),
                },
            },
        },
        .{
            .name = "set",
            .alias_names = &.{ "change" },
            .description = "Set/Change a Connection attribute for the specified Interface.",
            .cmd_group = "INTERFACE",
            .opt_groups = &.{ "CHANNEL", "MAC", "INTERFACE" },
            .sub_cmds_mandatory = false,
            .opts = &.{
                .{
                    .name = "channel",
                    .description = "Set the Channel of the given Interface. (Note, this will set the card to Up in Monitor mode)",
                    .opt_group = "CHANNEL",
                    .long_name = "channel",
                    .short_name = 'c',
                    .val = ValueT.ofType(usize, .{
                        .name = "chan",
                        .valid_fn = struct{
                            pub fn valCh(ch: usize, _: mem.Allocator) bool {
                                return nl._80211.validateChannel(ch);
                            }
                        }.valCh,
                    }),
                },
                .{
                    .name = "channel-width",
                    .description = "Set the Channel/Frequency Width (in MHz & Throughput) of the given Interface. (Note, this only works in conjunction with `--channel` or `--freq`)",
                    .opt_group = "CHANNEL",
                    .long_name = "channel-width",
                    .alias_long_names = &.{ "ch-width", "frequency-width", "freq-width" },
                    .short_name = 'C',
                    .val = ValueT.ofType(nl._80211.CHANNEL_WIDTH, .{}),
                },
                .{
                    .name = "frequency",
                    .description = "Set the frequency (in MHz) of the given Interface. (Note, this will set the card to Up in Monitor mode)",
                    .opt_group = "CHANNEL",
                    .long_name = "frequency",
                    .short_name = 'f',
                    .val = ValueT.ofType(usize, .{
                        .name = "freq",
                        .valid_fn = struct{
                            pub fn valFreq(freq: usize, _: mem.Allocator) bool {
                                return nl._80211.validateFreq(freq);
                            }
                        }.valFreq,
                    }),
                },
                .{
                    .name = "mac",
                    .description = "Set the MAC Address of the given Interface.",
                    .opt_group = "MAC",
                    .long_name = "mac",
                    .short_name = 'm',
                    .allow_empty = true,
                    .val = ValueT.ofType([6]u8, .{
                        .name = "address",
                        .parse_fn = parseMAC,
                    }),
                },
                .{
                    .name = "random_mac",
                    .description = "Set a Random MAC Address type for `--mac`. (Settings: `ll` = Link Local [default], `full` = Full Random, `oui` = Random Real OUI)",
                    .opt_group = "MAC",
                    .long_name = "random",
                    .short_name = 'r',
                    .allow_empty = true,
                    .val = ValueT.ofType(address.RandomMACKind, .{ .default_val = .ll }),
                },
                .{
                    .name = "oui",
                    .description = "Set an OUI Manufacturer type for `--mac`. (This based on the Manufacturer Column of the Wireshark MAC list. Default 'Intel')",
                    .opt_group = "MAC",
                    .long_name = "oui",
                    .short_name = 'o',
                    .val = ValueT.ofType([3]u8, .{
                        .default_val = .{ 0xF8, 0x63, 0xD9 },
                        .parse_fn = getOUI,
                    }),
                },
                .{
                    .name = "state",
                    .description = "Set the State of the given Interface. (UP, DOWN, BROADCAST, etc). (Note, multiple flags can be set simultaneously)",
                    .opt_group = "INTERFACE",
                    .long_name = "state",
                    .short_name = 's',
                    .val = ValueT.ofType(nl.route.IFF, .{
                        .set_behavior = .Multi,
                        .max_entries = 32,
                        .parse_fn = struct {
                            pub fn parseIFF(arg: []const u8, _: mem.Allocator) !nl.route.IFF {
                                var state_buf: [12]u8 = undefined;
                                if (ascii.isUpper(arg[0]) and ascii.isUpper(arg[1])) return meta.stringToEnum(nl.route.IFF, arg) orelse error.InvalidState;
                                const state = ascii.upperString(state_buf[0..], arg[0..@min(arg.len, 12)]);
                                return meta.stringToEnum(nl.route.IFF, state) orelse error.InvalidState;
                            }
                        }.parseIFF,
                    }),
                },
                .{
                    .name = "mode",
                    .description = "Set the Mode of the given Interface. (MONITOR, STATION, AP, etc)",
                    .opt_group = "INTERFACE",
                    .long_name = "mode",
                    .short_name = 'M',
                    .val = ValueT.ofType(nl._80211.IFTYPE, .{
                        .parse_fn = struct {
                            pub fn parseIFF(arg: []const u8, _: mem.Allocator) !nl._80211.IFTYPE {
                                var mode_buf: [12]u8 = undefined;
                                if (ascii.isUpper(arg[0]) and ascii.isUpper(arg[1])) return meta.stringToEnum(nl._80211.IFTYPE, arg) orelse error.InvalidMode;
                                const mode = ascii.upperString(mode_buf[0..], arg[0..@min(arg.len, 12)]);
                                return meta.stringToEnum(nl._80211.IFTYPE, mode) orelse error.InvalidMode;
                            }
                        }.parseIFF,
                    }),
                },
            },
        },
        .{
            .name = "add",
            .description = "Add a Connection attribute to the specified Interface.",
            .cmd_group = "INTERFACE",
            .opts = &.{
                .{
                    .name = "ip",
                    .description = "Add an IP Address to the given Interface.",
                    .long_name = "ip",
                    .val = ValueT.ofType(address.IPv4, .{
                        .parse_fn = parseIPv4,
                    }),
                },
                .{
                    .name = "route",
                    .description = "Add a Route to the given Interface. (A default gateway, '0.0.0.0', can be added using `default`)",
                    .long_name = "route",
                    .alias_long_names = &.{ "rt" },
                    .short_name = 'r',
                    .val = ValueT.ofType(address.IPv4, .{
                        .parse_fn = parseIPv4,
                    }),
                },
                .{
                    .name = "gateway",
                    .description = "Add a Gateway for the provided Route. (Used in conjuction with `--route`)",
                    .long_name = "gateway",
                    .alias_long_names = &.{ "gw", "via" },
                    .short_name = 'g',
                    .val = ValueT.ofType(address.IPv4, .{
                        .parse_fn = parseIPv4,
                    }),
                },
                //.{
                //    .name = "subnet",
                //    .description = "Specify a Subnet Mask (in CIDR or IP notation) for the IP Address or Route being added to given Interface. (Used in conjunction with `--ip` or `--route`. Default = 24)",
                //    .long_name = "subnet",
                //    .short_name = 's',
                //    .val = ValueT.ofType(u8, .{
                //        .default_val = 24,
                //        .parse_fn = address.parseCIDR,
                //    }),
                //},
            },
        },
        .{
            .name = "delete",
            .alias_names = &.{ "remove", "rm" },
            .description = "Delete/Remove a Connection attribute from the specified Interface.",
            .cmd_group = "INTERFACE",
            .opts = &.{
                .{
                    .name = "ip",
                    .description = "Remove an IP Address from the given Interface.",
                    .long_name = "ip",
                    .val = ValueT.ofType(address.IPv4, .{
                        .parse_fn = parseIPv4,
                    }),
                },
                .{
                    .name = "route",
                    .description = "Remove a Route from the given Interface.",
                    .long_name = "route",
                    .alias_long_names = &.{ "rt" },
                    .short_name = 'r',
                    .val = ValueT.ofType(address.IPv4, .{
                        .parse_fn = parseIPv4,
                    }),
                },
                .{
                    .name = "gateway",
                    .description = "Add a Gateway for the provided Route. (Used in conjuction with `--route`)",
                    .long_name = "gateway",
                    .alias_long_names = &.{ "gw", "via" },
                    .short_name = 'g',
                    .val = ValueT.ofType(address.IPv4, .{
                        .parse_fn = parseIPv4,
                    }),
                },
                //.{
                //    .name = "subnet",
                //    .description = "Specify a Subnet Mask to identify the IP Address or Route being removed from the given Interface. (Used in conjunction with `--ip` or `--route`)",
                //    .long_name = "subnet",
                //    .short_name = 's',
                //    .val = ValueT.ofType(u8, .{
                //        .default_val = 24,
                //        .parse_fn = address.parseCIDR,
                //    }),
                //},
            },
        },
        .{
            .name = "system",
            .description = "Manage System attributes.",
            .cmd_group = "SETTINGS",
            .sub_cmds = &.{
                .{
                    .name = "set",
                    .description = "Set System attributes.",
                    .opts = &.{
                        .{
                            .name = "hostname",
                            .description = "Set a new Hostname.",
                            .long_name = "hostname",
                            .short_name = 'H',
                            .val = ValueT.ofType([]const u8, .{}),
                        },
                    },
                },
            },
        },
        CommandT.from(@TypeOf(wpa.genKey), .{
            .cmd_name = "gen-key",
            .cmd_description = "Generate a WPA Key.",
            .cmd_group = "SETTINGS",
            .sub_descriptions = &.{
                .{ "protocol", "WiFi Network Security Protocol." },
                .{ "ssid", "WiFi Network SSID." },
                .{ "passphrase", "WiFi Network Passphrase." },
            },
        }),
    },
};


// Multi-use Arguments
/// Channels
const channels_opt: OptionT = .{
    .name = "channels",
    .description = "Specify channels to be used. (By default, all channels will be used.)",
    .short_name = 'c',
    .long_name = "channels",
    .val = ValueT.ofType(usize, .{
        .set_behavior = .Multi,
        .max_entries = 50,
        .valid_fn = struct {
            pub fn valCh(ch: usize, _: mem.Allocator) bool {
                return nl._80211.validateChannel(ch);
            }
        }.valCh,
    }),
};

// Function Wrappers
fn parseIPv4(arg: []const u8, _: mem.Allocator) !address.IPv4 {
    return try address.IPv4.fromStr(arg);
}

fn parseMAC(arg: []const u8, _: mem.Allocator) ![6]u8 {
    return try address.parseMAC(arg);
}

fn getOUI(arg: []const u8, _: mem.Allocator) ![3]u8 {
    return try oui.getOUI(arg);
}
