module jax.filters;


import std.algorithm;
import std.array;
import std.format;
import std.string;
import std.regex;
import std.utf;
import std.traits;


private @property bool validURL(string url) {
	import std.conv : to;

	if (url.empty) {
		return false;
	} else if (url.ptr[0] != '/') {
		auto idx = url.indexOf(':');
		if (idx <= 0)
			return false; // no protocol

		auto protocol = url[0..idx];
		url = url[idx+1..$];

		auto needsHost = false;

		switch (protocol) {
			case "http":
			case "https":
			case "ftp":
			case "spdy":
			case "sftp":
				if (!url.startsWith("//"))
					return false; // must start with protocol://...

				needsHost = true;
				url = url[2..$];
				goto default;
			case "file":
				if (!url.startsWith("//"))
					return false; // must start with protocol://...

				url = url[2..$];
				goto default;
			default:
				auto indexSlash = url.indexOf('/');
				if (indexSlash < 0)
					indexSlash = url.length;

				auto indexAt = url[0..indexSlash].indexOf('@');
				size_t indexHost = 0;
				if (indexAt >= 0) {
					indexHost = cast(size_t)indexAt + 1;
					auto sep = url[0..indexAt].indexOf(':');
					auto username = (sep >= 0) ? url[0..sep] : url[0..indexAt];
					if (username.empty)
						return false; // empty user name
				}

				auto host = url[indexHost..indexSlash];
				auto indexPort = host.indexOf(':');

				if (indexPort > 0) {
					if (indexPort >= host.length-1)
						return false; // empty port
					try {
						auto port = to!ushort(host[indexPort+1..$]);
					} catch {
						return false;
					}
					host = host[0..indexPort];
				}

				if (host.empty && needsHost)
					return false; // empty server name

				url = url[indexSlash..$];
		}
	}

	return true;
}


private struct FixedAppender(AT : E[], size_t Size = 512, E) {
	alias UE = Unqual!E;

	private UE[Size] data_;
	private size_t len_;

	static if (!is(E == immutable)) {
		void clear() {
			len_ = 0;
		}
	}

	void put(E x) {
		data_[len_++] = x;
	}

	static if (is(UE == char)) {
		void put(dchar x) {
			if (x < 0x80) {
				put(cast(char)x);
			} else {
				char[4] buf;
				auto len = std.utf.encode(buf, x);
				put(cast(AT)buf[0..len]);
			}
		}
	}

	static if (is(UE == wchar)) {
		void put(dchar x) {
			if (x < 0x80) {
				put(cast(wchar)x);
			} else {
				wchar[3] buf;
				auto len = std.utf.encode(buf, x);
				put(cast(AT)buf[0..len]);
			}
		}
	}

	void put(AT arr) {
		data_[len_..len_ + arr.length] = (cast(UE[])arr)[];
		len_ += arr.length;
	}

	@property AT data() {
		return cast(AT)data_[0..len_];
	}
}


auto fixedAppender(AT : E[], size_t Size = 512, E)() {
	return FixedAppender!(AT, Size, E)();
}


string concat(Args...)(Args args) if (args.length > 0) {
	static if (args.length > 1) {
		auto length = 0;
		auto precise = true;

		foreach(arg; args) {
			static if (isSomeString!(typeof(arg))) {
				length += arg.length;
			} else static if (isScalarType!(typeof(arg))) {
				length += 24;
			} else static if (isSomeChar!(typeof(arg))) {
				length += 6; // max unicode code length
			} else {
				length += 16;
				precise = false;
			}
		}

		enum MaxStackAlloc = 1024;

		if (precise && (length <= MaxStackAlloc)) {
			auto app = fixedAppender!(string, MaxStackAlloc);

			foreach(arg; args) {
				static if (isSomeString!(typeof(arg)) || isSomeChar!(typeof(arg))) {
					app.put(arg);
				} else {
					formattedWrite(&app, "%s", arg);
				}
			}
			return app.data.idup;
		} else {
			auto app = appender!string;
			app.reserve(length);

			foreach(arg; args) {
				static if (isSomeString!(typeof(arg)) || isSomeChar!(typeof(arg))) {
					app.put(arg);
				} else {
					formattedWrite(&app, "%s", arg);
				}
			}

			return app.data;
		}
	} else {
		static if (isSomeString!(typeof(arg)) || isSomeChar!(typeof(arg))) {
			return args[0];
		} else {
			formattedWrite(&app, "%s", arg);
		}
	}
}



enum FormatHTMLOptions {
	None			= 0,
	Escape			= 1 << 0,
	CreateLinks		= 1 << 1,
	Default			= None,
}


private __gshared {
	auto matchNewLine = ctRegex!(`\r\n|\n`, `g`);
	auto matchLink = ctRegex!(`\b((?:[\w-]+://?|www[.])[^\s()<>]+(?:\([\w\d]+\)|(?:[^\s\."'!?()<>]|/)))\b`, `gi`);
	auto matchEMail = ctRegex!(`(\b[a-z0-9._%+-]+(?:@|&#64;)[a-z0-9.-]+\.[a-z]{2,4}\b)`, `gi`);
}


string formatHTML(FormatHTMLOptions Options = FormatHTMLOptions.Default)(string x) {
	auto result = x;

	static if (Options & FormatHTMLOptions.Escape) {
		result = result.escapeHTML;
	}

	result = result.replaceAll(matchNewLine, "<br />");

	static if (Options & FormatHTMLOptions.CreateLinks) {
		static string createLink(Captures!(string) m) {
			auto url = m[0];
			if (url.indexOf("://") <= 0)
				url = concat("http://", url);

			auto urlShort = url;

			if (url.validURL) {
				if (url.length > 72)
					urlShort = concat(urlShort[0..70], "&hellip;");
				return format(`<a href="%s" target="nofollow">%s</a>`, url, urlShort);
			} else {
				return m[0];
			}
		}

		result = result.replaceAll!(createLink)(matchLink);
		result = result.replaceAll(matchEMail, "<a href=\"mailto:$1\">$1</a>");
	}

	return result;
}


string escapeHTML(string x) {
	auto app = appender!string;
	app.reserve(8 + x.length + (x.length >> 1));

	foreach (ch; x.byDchar) {
		switch (ch) {
		case '"':
			app.put("&quot;");
			break;
		case '\'':
			app.put("&#39;");
			break;
		case 'a': .. case 'z':
			goto case;
		case 'A': .. case 'Z':
			goto case;
		case '0': .. case '9':
			goto case;
		case ' ', '\t', '\n', '\r', '-', '_', '.', ':', ',', ';',
			'#', '+', '*', '?', '=', '(', ')', '/', '!',
			'%' , '{', '}', '[', ']', '$', '^', '~':
			app.put(cast(char)ch);
			break;
		case '<':
			app.put("&lt;");
			break;
		case '>':
			app.put("&gt;");
			break;
		case '&':
			app.put("&amp;");
			break;
		default:
			formattedWrite(&app, "&#x%02X;", cast(uint)ch);
			break;
		}
	}
	return app.data;
}


string escapeJS(string x) {
	auto app = appender!string;
	app.reserve(x.length + (x.length >> 1));

	foreach (ch; x.byDchar) {
		switch (ch) {
			case '\\':
				app.put(`\\`);
				break;
			case '\'':
				app.put(`\'`);
				break;
			case '\"':
				app.put(`\"`);
				break;
			case '\r':
				break;
			case '\n':
				app.put(`\n`);
				break;
			default:
				app.put(ch);
				break;
		}
	}
	return app.data;
}


string encodeURI(string x) {
	auto app = appender!string;
	app.reserve(8 + x.length + (x.length >> 1));

	encodeURI(app, x);

	return app.data;
}


void encodeURI(Appender)(ref Appender app, string x, const(char)[]ignoreChars = null) {
	foreach (i; 0..x.length) {
		switch (x.ptr[i]) {
		case 'A': .. case 'Z':
		case 'a': .. case 'z':
		case '0': .. case '9':
		case '-': case '_': case '.': case '~':
			app.put(x.ptr[i]);
			break;
		default:
			if (ignoreChars.canFind(x.ptr[i])) {
				app.put(x.ptr[i]);
			} else {
				formattedWrite(&app, "%%%02X", x.ptr[i]);
			}
			break;
		}
	}
}


string appendURIParam(string x, string param, string value) {
	if (x.indexOf('?') == -1)
		return concat(x, "?", param, "=", value);
	return concat(x, "&", param, "=", value);
}
