# export_ppm

Just a couple of functions in Zig that export image data, RGB/RGBA/grayscale/grayscale+alpha, 8 or 16 bits per channel, as PPM/PGM files. Not enough code to be called a library.

PPM and PGM are very simple graphic file formats, but they are widespread enough for popular editors, like [Gimp](https://www.gimp.org/), [Krita](https://krita.org) or [Adobe Photoshop](https://www.adobe.com/creativecloud/file-types/image/raster/ppm-file.html) to be able to open them. Meaning you can quickly dump whatever you want from your Zig programs as a PPM/PGM file and open it in an editor.

See https://en.wikipedia.org/wiki/Netpbm?useskin=vector, https://netpbm.sourceforge.net/doc/ppm.html.

**test_data_src** folder contains PNG images I used as test data, ignore them or use them however you want. I release them in public domain.

 **export_ppm.zig** is licensed under [the MIT License](https://en.wikipedia.org/w/index.php?title=MIT_License&useskin=vector).