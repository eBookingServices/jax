module mime;

import std.base64;
import std.range;
import std.string;


string extensionToMimeType(string ext) {
	switch(ext.toLower()) {
		case ".jpg":
		case ".jpeg":
			return "image/jpeg";
		case ".png":
			return "image/png";
		case ".gif":
			return "image/gif";
		case ".tga":
			return "image/targa";
		case ".tif":
		case ".tiff":
			return "image/tiff";
		default:
			break;
	}
	return null;
}


string mimeTypeToExtension(string mime) {
	switch(mime.toLower()) {
		case "image/jpg":
		case "image/jpeg":
		case "image/pjpeg":
			return ".jpg";
		case "image/x-png":
		case "image/png":
			return ".png";
		case "image/gif":
			return ".gif";
		case "image/x-targa":
		case "image/targa":
		case "image/tga":
			return ".tga";
		case "image/tif":
		case "image/tiff":
		case "image/x-tiff":
		case "image/x-tif":
			return ".tif";
		default:
			break;
	}
	return null;
}


string mimeEncode(string input) {
	Appender!string mime = appender!string;
	foreach (ref encoded; Base64.encoder(chunks(cast(ubyte[])input, 57))) {
		mime.put(encoded);
		mime.put("\r\n");
	}
	return mime.data();
}
