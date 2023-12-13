const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

pub const ColorType = enum
{
    gray,
    rgb,
    graya,
    rgba,
};

pub const ChannelSize = enum
{
    eightBpc,   // 8 bits per channel
    sixteenBpc, // 16 bits per channel
};

/// Save image buffer as binary ("Raw") PPM or PGM file,
/// depending on `clr_type` - RGB or grayscale.
/// Alpha channel is ignored if present (.graya, .rgba).
/// See https://en.wikipedia.org/wiki/Netpbm?useskin=vector#Description
///     https://netpbm.sourceforge.net/doc/ppm.html
/// Arguments:
/// fname    - Export file name. Extension (".pgm" or ".ppm", depending on `clr_type`) is appended automatically.
/// img_data - Image data array. If `clr_type` is .sixteenBpc, big-endian ("network") byte order is expected.
/// img_w    - Image width, in pixels.
/// img_h    - Image height, in pixels.
/// clr_type - Image color type.
/// ch_size  - How many bits is every image channel (R, G, B, Alpha) wide. 8 and 16 bits per channel
///            images are supported.
/// alloc8r  - Allocator, used for small buffers used by the function.
pub fn exportBinaryPpm(fname: []const u8, img_data: []const u8, img_w: u32, img_h: u32,
                       clr_type: ColorType, ch_size: ChannelSize,
                       alloc8r: std.mem.Allocator) !void
{
    const fext = switch (clr_type)
    {
        .gray, .graya => ".pgm",
        .rgb, .rgba   => ".ppm"
    };
    const magic_num = switch (clr_type)
    {
        .gray, .graya => "P5",
        .rgb, .rgba   => "P6"
    };
    const maxval: u16 = switch (ch_size)
    {
        .eightBpc   => 255,
        .sixteenBpc => 65535,
    };

    // Allocate at least 64 bytes so that we can reuse the buffer for the text part of the file, see below
    const tmp_buf = try alloc8r.alloc(u8, if (fname.len + fext.len > 64) fname.len + fext.len else 64);
    defer alloc8r.free(tmp_buf);
    const full_fname_sl = try std.fmt.bufPrint(tmp_buf, "{s}{s}", .{ fname, fext });
    // Whether the file will be created with read access -----v
    var f = try std.fs.cwd().createFile(full_fname_sl, .{ .read = false });
    defer f.close();

    // Max number of characters: 2+1+10+1+10+1+5 = 30. 64 bytes should be more than enough.
    const buf_slice = try std.fmt.bufPrint(tmp_buf, "{s}\n{d} {d}\n{d}\n", .{ magic_num, img_w, img_h, maxval });
    try f.writeAll(buf_slice);

    // Since both PNG and PPM/PGM store 16-bit channel values in big endian format,
    // we don't have to convert anything..
    if (clr_type == .gray or clr_type == .rgb) // No alpha channel
    {
        // ..just write image data as it is
        try f.writeAll(img_data);
    }
    else // .graya or .rgba - must remove alpha channel, since PPM/PGM files don't support it
    {
        const chan_num: u8 = switch (clr_type)
        {
            .graya => 2,
            .rgba  => 4,
            else   => unreachable
        };
        const bytes_per_chan: u8 = switch (ch_size) { .eightBpc => 1, .sixteenBpc => 2 };
        const bytes_pixel_wo_alpha = bytes_per_chan * (chan_num - 1); // bytes per pixel, not taking alpha channel into account
        const compacted_row_num_pixel_bytes = img_w * bytes_pixel_wo_alpha; // Don't add +1 byte for filter type

        // Allocate a buffer for one row of pixels without alpha channel
        const compacted_buf = try alloc8r.alloc(u8, compacted_row_num_pixel_bytes);
        defer alloc8r.free(compacted_buf);

        const bytes_per_pixel = bytes_per_chan * chan_num;
        const row_num_bytes = img_w * bytes_per_pixel;
        var i: u32 = 0;
        while (i < img_data.len) : (i += row_num_bytes)
        {
            // -- Copy each pixel, sans alpha channel, to compacted_buf packed tightly w/o alpha channel --
            // Skip the first byte, as it's the filter type byte.
            var r_idx: u32 = i;
            var next_free_idx: u32 = 0; // Index of the byte we move the next pixel to
            while (r_idx < i + row_num_bytes) : ({ r_idx += bytes_per_pixel; next_free_idx += bytes_pixel_wo_alpha; })
                @memcpy(compacted_buf[next_free_idx..(next_free_idx+bytes_pixel_wo_alpha)],
                        img_data[r_idx..(r_idx+bytes_pixel_wo_alpha)]);

            // Finally write the compacted row of pixels
            try f.writeAll(compacted_buf);
        }
    }
}

/// Save image buffer as ASCII ("Plain") PPM or PGM file,
/// depending on `clr_type` - RGB or grayscale.
/// Alpha channel is ignored if present (.graya, .rgba).
/// See https://en.wikipedia.org/wiki/Netpbm?useskin=vector#Description
///     https://netpbm.sourceforge.net/doc/ppm.html
/// Arguments:
/// fname    - Export file name. Extension (".pgm" or ".ppm", depending on `clr_type`) is appended automatically.
/// img_data - Image data array. If `clr_type` is .sixteenBpc, big-endian ("network") byte order is expected.
/// img_w    - Image width, in pixels.
/// img_h    - Image height, in pixels.
/// clr_type - Image color type.
/// ch_size  - How many bits is every image channel (R, G, B, Alpha) wide. 8 and 16 bits per channel
///            images are supported.
/// alloc8r  - Allocator, used for small buffers used by the function.
pub fn exportAsciiPpm(fname: []const u8, img_data: []const u8, img_w: u32, img_h: u32,
                      clr_type: ColorType, ch_size: ChannelSize,
                      alloc8r: std.mem.Allocator) !void
{
    const fext = switch (clr_type)
    {
        .gray, .graya => ".pgm",
        .rgb, .rgba   => ".ppm"
    };
    const magic_num = switch (clr_type)
    {
        .gray, .graya => "P2",
        .rgb, .rgba   => "P3"
    };
    const maxval: u16 = switch (ch_size)
    {
        .eightBpc   => 255,
        .sixteenBpc => 65535,
    };

    // Allocate at least 64 bytes so that we can reuse the buffer for the text part of the file, see below
    const tmp_buf = try alloc8r.alloc(u8, if (fname.len + fext.len > 64) fname.len + fext.len else 64);
    defer alloc8r.free(tmp_buf);
    const full_fname_sl = try std.fmt.bufPrint(tmp_buf, "{s}{s}", .{ fname, fext });
    // Whether the file will be created with read access -----v
    var f = try std.fs.cwd().createFile(full_fname_sl, .{ .read = false });
    defer f.close();

    // Max number of characters: 2+1+10+1+10+1+5 = 30. 64 bytes should be more than enough.
    const buf_slice = try std.fmt.bufPrint(tmp_buf, "{s}\n{d} {d}\n{d}\n", .{ magic_num, img_w, img_h, maxval });
    try f.writeAll(buf_slice);

    const chan_num: u8 = switch (clr_type)
    {
        .gray  => 1,
        .graya => 2,
        .rgb   => 3,
        .rgba  => 4
    };

    if (clr_type == .gray or clr_type == .rgb) // No alpha channel
    {
        if (ch_size == .sixteenBpc)
        {
            // 16 bits per channel, RGB or GRAYSCALE
            var i: u32 = 0;
            var chan_val: u16 = 0;
            var x: u32 = 1;
            while (i < img_data.len) : (i += 2)
            {
                chan_val = if (native_endian == .little) (@as(u16, img_data[i]) << 8) | img_data[i+1]
                    else img_data[i] | (@as(u16, img_data[i+1]) << 8);
                const separator: u8 = if (x == img_w * chan_num) '\n' else ' ';
                const str_sl = try std.fmt.bufPrint(tmp_buf, "{d}{c}", .{ chan_val, separator });
                try f.writeAll(str_sl);

                x += 1;
                if (x > img_w * chan_num) x = 1;
            }
        }
        else
        {
            // 8 bits per channel, RGB or GRAYSCALE
            var x: u32 = 1;
            for (img_data) |b|
            {
                const separator: u8 = if (x == img_w * chan_num) '\n' else ' ';
                const str_sl = try std.fmt.bufPrint(tmp_buf, "{d}{c}", .{ b, separator });
                try f.writeAll(str_sl);

                x += 1;
                if (x > img_w * chan_num) x = 1;
            }
        }
    }
    else // .graya or .rgba - must remove alpha channel, since PPM/PGM files don't support it
    {
        if (ch_size == .sixteenBpc) // 16 bits per channel, RGBA or GRAYSCALE+ALPHA
        {
            var chan_val: u16 = 0;
            var chan_idx: u8 = 0;
            var i: u32 = 0;
            var x: u32 = 1;
            while (i < img_data.len) : (i += 2)
            {
                if (chan_idx < chan_num - 1)
                {
                    chan_val = if (native_endian == .little) (@as(u16, img_data[i]) << 8) | img_data[i+1]
                        else img_data[i] | (@as(u16, img_data[i+1]) << 8);
                    const separator: u8 = if (x == img_w * (chan_num - 1)) '\n' else ' ';
                    const str_sl = try std.fmt.bufPrint(tmp_buf, "{d}{c}", .{ chan_val, separator });
                    try f.writeAll(str_sl);
                    chan_idx += 1;

                    x += 1;
                    if (x > img_w * (chan_num - 1)) x = 1;
                }
                else
                    chan_idx = 0;
            }
        }
        else // 8 bits per channel, RGBA or GRAYSCALE+ALPHA
        {
            var chan_idx: u8 = 0;
            var x: u32 = 1;
            for (img_data) |b|
            {
                if (chan_idx < chan_num - 1)
                {
                    const separator: u8 = if (x == img_w * (chan_num - 1)) '\n' else ' ';
                    const str_sl = try std.fmt.bufPrint(tmp_buf, "{d}{c}", .{ b, separator });
                    try f.writeAll(str_sl);
                    chan_idx += 1;

                    x += 1;
                    if (x > img_w * (chan_num - 1)) x = 1;
                }
                else
                    chan_idx = 0;
            }
        }
    } // else // .graya or .rgba
}

// ------------------ Tests ------------------

// ---- Grayscale ----

test "Binary GRAYSCALE 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0xff, 0xff, 0x00,
        0x00, 0xe0, 0x00, 0x00, 0xe0,
        0x00, 0x00, 0xad, 0xad, 0x00,
        0x00, 0x85, 0x00, 0x00, 0x85,
        0x00, 0x00, 0x52, 0x52, 0x00,
    };
    std.debug.print("Exporting gray_8bpc_bin.pgm\n", .{});
    try exportBinaryPpm("gray_8bpc_bin", img[0..], 5, 5, .gray, .eightBpc, std.testing.allocator);
}

test "ASCII GRAYSCALE 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0xff, 0xff, 0x00,
        0x00, 0xe0, 0x00, 0x00, 0xe0,
        0x00, 0x00, 0xad, 0xad, 0x00,
        0x00, 0x85, 0x00, 0x00, 0x85,
        0x00, 0x00, 0x52, 0x52, 0x00,
    };
    std.debug.print("Exporting gray_8bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("gray_8bpc_ascii", img[0..], 5, 5, .gray, .eightBpc, std.testing.allocator);
}

test "Binary GRAYSCALE 16 bpc"
{
    const img = [_]u8
    {
        0xff, 0xff, 0x00, 0x00, 0xff, 0xed, 0xff, 0x9f, 0xff, 0xeb,
        0xd8, 0xbc, 0x00, 0x00, 0xd9, 0x68, 0x00, 0x00, 0x00, 0x00,
        0xb2, 0x40, 0x00, 0x00, 0xb2, 0x37, 0xb2, 0x47, 0xb1, 0xdd,
        0x81, 0x3d, 0x00, 0x00, 0x8b, 0x71, 0x00, 0x00, 0x8a, 0xd4,
        0x5a, 0xa0, 0x00, 0x00, 0x5a, 0x57, 0x5a, 0x4e, 0x5a, 0xa3,
    };
    std.debug.print("Exporting gray_16bpc_bin.pgm\n", .{});
    try exportBinaryPpm("gray_16bpc_bin", img[0..], 5, 5, .gray, .sixteenBpc, std.testing.allocator);
}

test "ASCII GRAYSCALE 16 bpc"
{
    const img = [_]u8
    {
        0xff, 0xff, 0x00, 0x00, 0xff, 0xed, 0xff, 0x9f, 0xff, 0xeb,
        0xd8, 0xbc, 0x00, 0x00, 0xd9, 0x68, 0x00, 0x00, 0x00, 0x00,
        0xb2, 0x40, 0x00, 0x00, 0xb2, 0x37, 0xb2, 0x47, 0xb1, 0xdd,
        0x81, 0x3d, 0x00, 0x00, 0x8b, 0x71, 0x00, 0x00, 0x8a, 0xd4,
        0x5a, 0xa0, 0x00, 0x00, 0x5a, 0x57, 0x5a, 0x4e, 0x5a, 0xa3,
    };
    std.debug.print("Exporting gray_8bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("gray_16bpc_ascii", img[0..], 5, 5, .gray, .sixteenBpc, std.testing.allocator);
}

test "Binary GRAYSCALE+ALPHA 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00,
        0x00, 0x00, 0xd3, 0xff, 0x00, 0x00, 0x00, 0x00, 0xd2, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x9b, 0xff, 0x9b, 0xff, 0x00, 0x00,
        0x00, 0x00, 0x65, 0xff, 0x00, 0x00, 0x00, 0x00, 0x65, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x32, 0xff, 0x32, 0xff, 0x00, 0x00,
    };
    std.debug.print("Exporting graya_8bpc_bin.pgm\n", .{});
    try exportBinaryPpm("graya_8bpc_bin", img[0..], 5, 5, .graya, .eightBpc, std.testing.allocator);
}

test "ASCII GRAYSCALE+ALPHA 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00,
        0x00, 0x00, 0xd3, 0xff, 0x00, 0x00, 0x00, 0x00, 0xd2, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x9b, 0xff, 0x9b, 0xff, 0x00, 0x00,
        0x00, 0x00, 0x65, 0xff, 0x00, 0x00, 0x00, 0x00, 0x65, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x32, 0xff, 0x32, 0xff, 0x00, 0x00,
    };
    std.debug.print("Exporting graya_8bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("graya_8bpc_ascii", img[0..], 5, 5, .graya, .eightBpc, std.testing.allocator);
}

test "Binary GRAYSCALE+ALPHA 16 bpc"
{
    const img = [_]u8
    {
        0xff, 0xc3, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xc4, 0xff, 0xff, 0xff, 0xb5, 0xff, 0xff, 0xff, 0xfb, 0xff, 0xff,
        0xc8, 0xb2, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xc9, 0x32, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x92, 0x44, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x92, 0x93, 0xff, 0xff, 0x91, 0xfa, 0xff, 0xff, 0x92, 0x31, 0xff, 0xff,
        0x69, 0x3b, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x69, 0x3d, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x69, 0x47, 0xff, 0xff,
        0x31, 0xcb, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x31, 0xc6, 0xff, 0xff, 0x32, 0x11, 0xff, 0xff, 0x32, 0x1e, 0xff, 0xff,
    };
    std.debug.print("Exporting graya_16bpc_bin.pgm\n", .{});
    try exportBinaryPpm("graya_16bpc_bin", img[0..], 5, 5, .graya, .sixteenBpc, std.testing.allocator);
}

test "ASCII GRAYSCALE+ALPHA 16 bpc"
{
    const img = [_]u8
    {
        0xff, 0xc3, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xc4, 0xff, 0xff, 0xff, 0xb5, 0xff, 0xff, 0xff, 0xfb, 0xff, 0xff,
        0xc8, 0xb2, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xc9, 0x32, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x92, 0x44, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x92, 0x93, 0xff, 0xff, 0x91, 0xfa, 0xff, 0xff, 0x92, 0x31, 0xff, 0xff,
        0x69, 0x3b, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x69, 0x3d, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x69, 0x47, 0xff, 0xff,
        0x31, 0xcb, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x31, 0xc6, 0xff, 0xff, 0x32, 0x11, 0xff, 0xff, 0x32, 0x1e, 0xff, 0xff,
    };
    std.debug.print("Exporting graya_16bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("graya_16bpc_ascii", img[0..], 5, 5, .graya, .sixteenBpc, std.testing.allocator);
}

// ---- RGB ----

test "Binary RGB 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xe3, 0x00, 0xff, 0xe4, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xff, 0xa8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xa9, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x92, 0x00, 0xff, 0x93, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xfa, 0x82, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfa, 0x82, 0x06,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe6, 0x6d, 0x1e, 0xe6, 0x6d, 0x1e, 0x00, 0x00, 0x00,
    };
    std.debug.print("Exporting rgb_8bpc_bin.pgm\n", .{});
    try exportBinaryPpm("rgb_8bpc_bin", img[0..], 5, 5, .rgb, .eightBpc, std.testing.allocator);
}

test "ASCII RGB 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xe3, 0x00, 0xff, 0xe4, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xff, 0xa8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xa9, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x92, 0x00, 0xff, 0x93, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xfa, 0x82, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfa, 0x82, 0x06,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe6, 0x6d, 0x1e, 0xe6, 0x6d, 0x1e, 0x00, 0x00, 0x00,
    };
    std.debug.print("Exporting rgb_8bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("rgb_8bpc_ascii", img[0..], 5, 5, .rgb, .eightBpc, std.testing.allocator);
}

test "Binary RGB 16 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x78, 0x69, 0x61, 0x7b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x31, 0x62, 0x49, 0x00, 0x30, 0x78, 0x35, 0x62, 0x0d, 0x00, 0x00, 0x78, 0x6e, 0x62, 0x54,
        0x00, 0x1f, 0x9d, 0xce, 0x54, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9e, 0x51, 0x54, 0x32, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x1e, 0xbc, 0x4e, 0x48, 0xad, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x75, 0xbc, 0x3b, 0x48, 0x5f, 0x00, 0x31, 0xbc, 0x8e, 0x48, 0xef, 0x00, 0x00, 0xbc, 0x75, 0x49, 0x01,
        0x00, 0x00, 0xda, 0x6e, 0x3d, 0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe1, 0xea, 0x3a, 0x87, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x65, 0xe1, 0xbb, 0x3a, 0xa4,
        0x00, 0x00, 0xff, 0xff, 0x2f, 0xba, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3e, 0xff, 0xff, 0x2f, 0xc0, 0x00, 0x00, 0xff, 0xff, 0x2f, 0xc1, 0x00, 0x00, 0xff, 0xbf, 0x2f, 0x1c,
    };
    std.debug.print("Exporting rgb_16bpc_bin.pgm\n", .{});
    try exportBinaryPpm("rgb_16bpc_bin", img[0..], 5, 5, .rgb, .sixteenBpc, std.testing.allocator);
}

test "ASCII RGB 16 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x78, 0x69, 0x61, 0x7b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x31, 0x62, 0x49, 0x00, 0x30, 0x78, 0x35, 0x62, 0x0d, 0x00, 0x00, 0x78, 0x6e, 0x62, 0x54,
        0x00, 0x1f, 0x9d, 0xce, 0x54, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9e, 0x51, 0x54, 0x32, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x1e, 0xbc, 0x4e, 0x48, 0xad, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x75, 0xbc, 0x3b, 0x48, 0x5f, 0x00, 0x31, 0xbc, 0x8e, 0x48, 0xef, 0x00, 0x00, 0xbc, 0x75, 0x49, 0x01,
        0x00, 0x00, 0xda, 0x6e, 0x3d, 0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe1, 0xea, 0x3a, 0x87, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x65, 0xe1, 0xbb, 0x3a, 0xa4,
        0x00, 0x00, 0xff, 0xff, 0x2f, 0xba, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3e, 0xff, 0xff, 0x2f, 0xc0, 0x00, 0x00, 0xff, 0xff, 0x2f, 0xc1, 0x00, 0x00, 0xff, 0xbf, 0x2f, 0x1c,
    };
    std.debug.print("Exporting rgb_8bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("rgb_16bpc_ascii", img[0..], 5, 5, .rgb, .sixteenBpc, std.testing.allocator);
}

test "Binary RGB+ALPHA 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5e, 0x5e, 0xff, 0xff, 0x5f, 0x5e, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x5d, 0x45, 0xea, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5d, 0x46, 0xea, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5c, 0x32, 0xd8, 0xff, 0x5c, 0x32, 0xd8, 0xff, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x5b, 0x18, 0xc3, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5b, 0x19, 0xc3, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5b, 0x00, 0xae, 0xff, 0x5b, 0x00, 0xae, 0xff, 0x00, 0x00, 0x00, 0x00,
    };
    std.debug.print("Exporting rgba_8bpc_bin.pgm\n", .{});
    try exportBinaryPpm("rgba_8bpc_bin", img[0..], 5, 5, .rgba, .eightBpc, std.testing.allocator);
}

test "ASCII RGB+ALPHA 8 bpc"
{
    const img = [_]u8
    {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5e, 0x5e, 0xff, 0xff, 0x5f, 0x5e, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x5d, 0x45, 0xea, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5d, 0x46, 0xea, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5c, 0x32, 0xd8, 0xff, 0x5c, 0x32, 0xd8, 0xff, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x5b, 0x18, 0xc3, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5b, 0x19, 0xc3, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5b, 0x00, 0xae, 0xff, 0x5b, 0x00, 0xae, 0xff, 0x00, 0x00, 0x00, 0x00,
    };
    std.debug.print("Exporting rgba_8bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("rgba_8bpc_ascii", img[0..], 5, 5, .rgba, .eightBpc, std.testing.allocator);
}

test "Binary RGB+ALPHA 16 bpc"
{
    const img = [_]u8
    {
        0xff, 0xda, 0x00, 0x59, 0x7e, 0x51, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x80, 0x00, 0x00, 0x7e, 0x68, 0xff, 0xff, 0xff, 0xf3, 0x00, 0x00, 0x7e, 0x53, 0xff, 0xff, 0xff, 0xd7, 0x00, 0x00, 0x7d, 0xfc, 0xff, 0xff,
        0xe1, 0x77, 0x00, 0x56, 0x63, 0x1a, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe1, 0xc4, 0x00, 0x14, 0x63, 0xdd, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xbb, 0xc8, 0x00, 0x45, 0x41, 0xf8, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xbc, 0x4d, 0x00, 0x71, 0x42, 0x49, 0xff, 0xff, 0xbb, 0xec, 0x00, 0x00, 0x42, 0x17, 0xff, 0xff, 0xbc, 0x70, 0x00, 0x00, 0x42, 0x6b, 0xff, 0xff,
        0x96, 0xcd, 0x00, 0x00, 0x21, 0x30, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x96, 0x71, 0x00, 0x00, 0x21, 0xa6, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9d, 0xd2, 0x00, 0x00, 0x27, 0x86, 0xff, 0xff,
        0x78, 0xd2, 0x00, 0x00, 0x06, 0xf7, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x9d, 0x00, 0x47, 0x07, 0x09, 0xff, 0xff, 0x78, 0x36, 0x00, 0x00, 0x06, 0x49, 0xff, 0xff, 0x78, 0xdf, 0x00, 0x4a, 0x06, 0x9f, 0xff, 0xff,
    };
    std.debug.print("Exporting rgba_16bpc_bin.pgm\n", .{});
    try exportBinaryPpm("rgba_16bpc_bin", img[0..], 5, 5, .rgba, .sixteenBpc, std.testing.allocator);
}

test "ASCII RGB+ALPHA 16 bpc"
{
    const img = [_]u8
    {
        0xff, 0xda, 0x00, 0x59, 0x7e, 0x51, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x80, 0x00, 0x00, 0x7e, 0x68, 0xff, 0xff, 0xff, 0xf3, 0x00, 0x00, 0x7e, 0x53, 0xff, 0xff, 0xff, 0xd7, 0x00, 0x00, 0x7d, 0xfc, 0xff, 0xff,
        0xe1, 0x77, 0x00, 0x56, 0x63, 0x1a, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe1, 0xc4, 0x00, 0x14, 0x63, 0xdd, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xbb, 0xc8, 0x00, 0x45, 0x41, 0xf8, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xbc, 0x4d, 0x00, 0x71, 0x42, 0x49, 0xff, 0xff, 0xbb, 0xec, 0x00, 0x00, 0x42, 0x17, 0xff, 0xff, 0xbc, 0x70, 0x00, 0x00, 0x42, 0x6b, 0xff, 0xff,
        0x96, 0xcd, 0x00, 0x00, 0x21, 0x30, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x96, 0x71, 0x00, 0x00, 0x21, 0xa6, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9d, 0xd2, 0x00, 0x00, 0x27, 0x86, 0xff, 0xff,
        0x78, 0xd2, 0x00, 0x00, 0x06, 0xf7, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x9d, 0x00, 0x47, 0x07, 0x09, 0xff, 0xff, 0x78, 0x36, 0x00, 0x00, 0x06, 0x49, 0xff, 0xff, 0x78, 0xdf, 0x00, 0x4a, 0x06, 0x9f, 0xff, 0xff,
    };
    std.debug.print("Exporting rgba_16bpc_ascii.pgm\n", .{});
    try exportAsciiPpm("rgba_16bpc_ascii", img[0..], 5, 5, .rgba, .sixteenBpc, std.testing.allocator);
}