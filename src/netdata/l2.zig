//! Layer 2 Types & Functions for DisCo.

const std = @import("std");
const mem = std.mem;

const utils = @import("../utils.zig");
const c = utils.toStruct;

/// Ethernet Frame
/// Reference: [Wikipedia - Ethernet Frame](https://en.wikipedia.org/wiki/Ethernet_frame#Header)
pub const Eth = struct {
    /// Ether Types/Protocols
    /// Reference: [Wikipedia - EtherType Values](https://en.wikipedia.org/wiki/EtherType#Values)
    pub const ETH_P = enum(u16) {
        ALL = 0x0003,
        IPv4 = 0x0800,
        ARP = 0x0806,
        IPv6 = 0x86DD,
        PAE = 0x888E,
    };

    /// Ethernet Header
    pub const Header = extern struct {
        dst_mac_addr: [6]u8,
        src_mac_addr: [6]u8,
        ether_type: u16,
    };

    /// Ethernet Footer
    pub const Footer = packed struct(u32){
        eth_frame_check_seq: u32 = 0,
    };
};

pub const EAPOL = struct {
    pub const EAP = enum(u8) {
        PACKET = 0x00,
        START = 0x01,
        LOGOFF = 0x02,
        KEY = 0x03,
        ALERT = 0x04,
    };

    pub const Header = packed struct {
        /// Protocol version, typically 0x01 or 0x02 for WPA2
        protocol_version: u8,
        /// EAPOL Packet Type
        packet_type: u8,
        /// Length of the EAPOL payload (excluding Ethernet header)
        packet_length: u16,
    };

    pub const KeyFrame = packed struct {
        /// Key Info Flags (In Big Endian)
        pub const KeyInfo = enum(u16) {
            /// Bit 0-2: Descriptor Version 1 (e.g., TKIP)
            Version1 = 0x0001,
            /// Bit 0-2: Descriptor Version 2 (e.g., AES-CCMP)
            Version2 = 0x0002,
            /// Bit 0-2: Descriptor Version 3 (e.g., AES-GCMP, WPA3)
            Version3 = 0x0003,
            /// Bit 3: Pairwise key (1) or Group key (0)
            KeyTypePairwise = 0x0008,
            /// Bit 6: Indicates if the key should be installed
            Install = 0x0040,
            /// Bit 7: Set if the frame is from the AP (authenticator)
            Ack = 0x0080,
            /// Bit 8: Indicates if the Key MIC is valid
            MIC = 0x0100,
            /// Bit 9: Secure
            Secure = 0x200,
            /// Bit 13: Set if Key Data is encrypted with KEK
            EncryptedData = 0x1000,
        };

        /// Key descriptor type, usually 0x02 for WPA2
        descriptor_type: u8, 
        /// Key Information flags
        key_info: u16,
        /// Length of the encryption key
        key_len: u16,
        /// Prevents replay attacks
        replay_counter: u64,
        /// Random nonce for key exchange
        //key_nonce: [32]u8,
        key_nonce: u256,
        /// Initialization vector (often zero in WPA2)
        //key_iv: [16]u8,
        key_iv: u128,
        /// Replay sequence counter
        key_rsc: u64,
        /// Reserved, usually unused in WPA2-Personal
        key_id: u64,
        /// Message Integrity Code for frame authenticity
        //key_mic: [16]u8,
        key_mic: u128,
        /// Length of the Key Data field
        key_data_len: u16,
    };
};

/// ARP - [IETF RFC 826](https://datatracker.ietf.org/doc/html/rfc826)
pub const ARP = struct {
    pub const Header = extern struct {
        hw_type: u16 = 1, // ARPHRD_ETHER,
        proto_type: u16 = 0x0800,
        hw_addr_len: u8 = 6,
        proto_addr_len: u8 = 4,
        op_code: u16 = OpCodes.REQUEST,
        sender_hw_addr: [6]u8 = .{ 0 } ** 6,
        sender_proto_addr: u32 = 0,
        tgt_hw_addr: [6]u8 = .{ 0 } ** 6,
        tgt_proto_addr: u32 = 0,
    };

    pub const OpCodes = enum(u16) {
        REQUEST = 1,
        REPLY = 2,
    };
};
