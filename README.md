# export_ppm

Just a couple of functions in Zig that export image data, RGB/RGBA/grayscale/grayscale+alpha (but alpha channel is ignored), 8 or 16 bits per channel, as PPM/PGM files. Not enough code to be called a library.

PPM and PGM are very simple graphic file formats, but they are widespread enough for popular editors, like [Gimp](https://www.gimp.org/), [Krita](https://krita.org) or [Adobe Photoshop](https://www.adobe.com/creativecloud/file-types/image/raster/ppm-file.html) to be able to open them. Meaning you can quickly dump whatever you want from your Zig programs as a PPM/PGM file and open it in an editor.

See https://en.wikipedia.org/wiki/Netpbm?useskin=vector, https://netpbm.sourceforge.net/doc/ppm.html.

Check out the tests in  `export_ppm.zig` for examples of use.

**test_data_src** folder contains PNG images I used as test data, ignore them or use them however you want. I release them in public domain.

**export_ppm.zig** is licensed under [the MIT License](https://en.wikipedia.org/w/index.php?title=MIT_License&useskin=vector).

Just drop `export_ppm.zig` into your project and add `const eppm = @import("export_ppm.zig");`, or use the Zig package manager:

1. In your project's `build.zig.zon`, in `.dependencies`, add

   ```zig
   .export_ppm =
   .{
       .url = "https://github.com/Durobot/export_ppm/archive/<GIT COMMIT HASH, 40 HEX DIGITS>.tar.gz",
       .hash = "<ZIG PACKAGE HASH, 68 HEX DIGITS>" // Use arbitrary hash, get correct hash from the error 
   }
   ```

2. In your project's `build.zig`, in `pub fn build`, before `b.installArtifact(exe);`, add

   ```zig
   const eppm = b.dependency("export_ppm",
   .{
       .target = target,
       .optimize = optimize,
   });
   exe.root_module.addImport("export_ppm", eppm.module("export_ppm"));
   ```

3. Add `const eppm = @import("export_ppm");`in your source file(s).

4. Build your project with `zig build`, as you normally do.