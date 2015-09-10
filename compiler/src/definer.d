module definer;


import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.range;
import std.string;


import context;
import lexer;
import mime;
import tags;
import token;
import utils;


struct Definer {
	struct Options {
		bool lines;
		string[] search;
		string[]* deps;
	}

	this(Options options) {
		this.options = options;
	}

	static string process(string fileName, Options options) {
		auto contents = Definer.getFileContents(fileName, options.search);
		return Definer(options).processString(contents.fileName, 1, contents.content);
	}

private:
	string processString(string sourceName, size_t line, string source) {
		try {
			auto result = parseSource(sourceName, line, source);
			if (options.lines && !isAllWhite(result))
				result = lineInfo(sourceName, line) ~ result;

			if (options.deps)
				*options.deps ~= deps.keys;
			return result;
		} catch(ParserException parserError) {
			auto error = concat(parserError.context.sourceName, '(', parserError.context.line, "): ", parserError.msg);
			foreach_reverse(context; contextStack)
					error = concat(error, "\n> ", context.sourceName, '(', context.line, ')');

			throw new Exception(error);
		}
	}

	string parseSource(string sourceName, size_t line, string source) {
		auto context = new Context(sourceName, source, line);
		contextStack ~= context;
		scope(exit) --contextStack.length;

		Appender!string result;
		result.reserve(64 * 1024);

		const size_t end = source.length - min(Tag.OpenTag.length, Tag.CloseTag.length);
		while (context.cursor < end) {
			auto remaining = context.remaining();
			auto indexOpen = remaining.indexOf(Tag.OpenTag);
			while (indexOpen != -1) {
				auto tag = remaining[indexOpen + Tag.OpenTag.length..indexOpen + Tag.OpenTag.length + 1];
				if ((tag == Tag.Define) || (tag == Tag.Include))
					break;
				indexOpen = remaining.indexOf(Tag.OpenTag, indexOpen + Tag.OpenTag.length);
			}
			if (indexOpen == -1)
				break;

			if (!context.defining)
				result.put(remaining[0..indexOpen]);
			context.advance(indexOpen);

			const size_t contentStart = indexOpen + Tag.OpenTag.length;
			auto indexClose = remaining.indexOf(Tag.CloseTag, contentStart);
			while (indexClose != -1) {
				if (balancedQuotes(remaining[contentStart..indexClose]))
					break;

				indexClose = remaining.indexOf(Tag.CloseTag, indexClose + Tag.CloseTag.length);
			}

			if (indexClose == -1)
				throw new ParserException(concat("missing '", cast(string)Tag.CloseTag, "' to close tag '", cast(string)Tag.OpenTag, "'"), context);

			context.advance(Tag.OpenTag.length);
			indexClose -= contentStart;

			auto replaced = replacer(source[context.cursor..context.cursor + indexClose], context);
			if (!context.defining)
				result.put(replaced);
			context.advance(indexClose + Tag.CloseTag.length);
		}
		context.expectTagClosed();

		result.put((context.cursor > 0) ? context.remaining() : source);

		return result.data();
	}


	auto include(string content, Context context) {
		auto embed = ((content.length > 1) && (content[1] == content[0])) ? 1 : 0;
		string[] filters;
		auto pipe = content.lastIndexOf("|");
		auto end = (pipe != -1) ? pipe : content.length;
		if (pipe != -1)
			filters = content[pipe + 1..$].split(',');

		auto fileName = content[1 + embed..end].strip;
		auto fixedFileName = fileName;
		string contents;

		if (extension(fileName).empty)
			fixedFileName = concat(fileName, ".html");

		auto pcontents = fileName in deps;
		if (!pcontents) {
			pcontents = fixedFileName in deps;
			if (pcontents)
				fileName = fixedFileName;
		}

		if (!embed) {
			auto cyclic = fixedFileName == context.sourceName;
			if (!cyclic) {
				foreach(size_t i; 0..contextStack.length) {
					auto prevContext = contextStack[i];
					if (prevContext.sourceName == fixedFileName) {
						cyclic = true;
						break;
					}
				}
			}

			if (cyclic)
				throw new ParserException(format("cyclic dependency in file '%s'", fixedFileName), context);
		}

		if (!pcontents) {
			while (true) {
				try {
					auto fcontents = getFileContents(fileName, options.search, embed != 0);
					fileName = fcontents.fileName;
					contents = fcontents.content;
				} catch(Exception e) {
					if (fileName == fixedFileName)
						throw new ParserException(format("failed to open %s file '%s'", embed ? "embedded" : "include", content[1 + embed..$].strip), context);
					fileName = fixedFileName;
					continue;
				}

				deps[fileName] = contents;
				break;
			}
		} else {
			contents = *pcontents;
		}

		if (!filters.empty) {
			foreach(i, filter; filters) {
				filter = filter.strip;
				// note: if you add a filter here, remember to update parser.d if applicable
				switch (filter) {
					case "capitalize":
						contents = contents.capitalize;
						break;
					case "lower":
						contents = contents.toLower;
						break;
					case "upper":
						contents = contents.toUpper;
						break;
					case "none":
						break;
					case "html":
						contents = contents.escapeHTML;
						break;
					case "format_html":
						content = contents.formatHTML!(FormatHTMLOptions.Escape);
						break;
					case "format_html_links":
						content = contents.formatHTML!(FormatHTMLOptions.Escape | FormatHTMLOptions.CreateLinks);
						break;
					case "js":
						contents = contents.escapeJS;
						break;
					case "url":
						contents = contents.encodeURI;
						break;
					case "token_url":
						contents = contents.appendURIParam("v", token.get);
						break;
					default:
						throw new ParserException(concat("invalid compile-time filter '", filter, "'"), context);
				}
			}
		}

		string result;
		if (!embed) {
			result = processString(fileName, 1, contents);
			if (options.lines && !isAllWhite(result))
				result ~= lineInfo(context.sourceName, context.line);
		} else {
			auto mime = extensionToMimeType(extension(fixedFileName));
			if (!mime.length)
				throw new ParserException(format("failed to deduce mime-type for embeded file '%s' - supported extensions are .jpg, .jpeg, .png, .tga and .gif", content[1 + embed..$].strip), context);

			result = concat("data:", mime, ";base64,", mimeEncode(contents));
		}
		return result;
	}

	auto define(string content, Context context) {
		auto lex = Lexer(cast(ubyte[])content[1..$]);
		try {
			auto tok = lex.expect("/", Tok.Identifier);
			if (tok == Tok.Identifier) {
				if (lex.value == "def") {
					def(lex, content, context);
				} else if (lex.value == "undef") {
					undef(lex, context);
				} else {
					// keep these for parser
					if ((lex.value == "set") || (lex.value == "push") || (lex.value == "pop"))
						return concat("{{", content, "}}");

					if (!context.defining)
						return expand(lex, context);
				}
			} else {
				close(lex, context);
			}
		} catch (LexerException e) {
			throw new ParserException(e.msg, context);
		}

		return null;
	}


	void def(ref Lexer lex, string content, Context context) {
		auto decl = parseDef(lex, context);

		auto pdef = decl.name in defs;
		if (pdef) {
			if ((pdef.sourceName != decl.sourceName) || (pdef.line != decl.line))
				throw new ParserException(format("redefinition of macro '%s' - first defined in '%s(%d)' - if this is intended undefine first", decl.name, decl.sourceName, decl.line), context);
		}

		Def def;
		def.sourceName = decl.sourceName;
		def.line = decl.line;
		def.args = decl.args;
		if (decl.inline) {
			def.flags = Def.Flags.Inline;
			def.value = decl.value;
		} else {
			def.flags = Def.Flags.NotYetDefined;
			context.tagOpen(content[0..1], content[1..$]);
		}

		defs[decl.name] = def;
	}

	void undef(ref Lexer lex, Context context) {
		lex.popFront;
		lex.expect(Tok.Identifier);
		auto name = lex.value;

		auto pdef = name in defs;
		if (!pdef)
			throw new ParserException(concat("trying to undefine unknown macro '", name, "'"), context);
		if (pdef.flags & Def.Flags.NotYetDefined)
			throw new ParserException(concat("trying to undefine macro '", name, "' inside it's own definition"), context);

		defs.remove(name);
	}


	void close(ref Lexer lex, Context context) {
		lex.popFront;
		lex.expect(Tok.EndOfInput);

		auto tag = context.tagClose();

		lex = Lexer(cast(ubyte[])tag.content);
		auto decl = parseDef(lex, context);

		size_t start = tag.cursor + Tag.Define.length + Tag.CloseTag.length + tag.content.length;
		size_t end = context.cursor - Tag.OpenTag.length;
		auto value = context.source[start..end];

		auto pdef = decl.name in defs;
		assert(pdef);
		assert(pdef.flags & Def.Flags.NotYetDefined);

		pdef.value = value;
		pdef.flags &= ~Def.Flags.NotYetDefined;
	}


	auto expandArg(string name, Context context) {
		if (name[0] == '`') {
			assert(name[$-1] == name[0]);
			return name[1..$-1];
		}
		if ((name[0] == '\"') || (name[0] == '\'')) {
			assert(name[$-1] == name[0]);
			return name;
		}

		auto parg = name in args;
		if (parg)
			return *parg;

		auto pdef = name in defs;
		if (pdef) {
			auto argsSaved = args;
			args = null;
			auto result = processString(pdef.sourceName, pdef.line, pdef.value);
			args = argsSaved;
			return result;
		}

		throw new ParserException(concat("unknown argument '", name, "'"), context);
	}


	auto expand(ref Lexer lex, Context context) {
		auto name = lex.value;
		auto parg = name in args;
		if (parg)
			return *parg;

		auto pdef = name in defs;
		if (!pdef)
			throw new ParserException(concat("unknown macro '", name, "'"), context);

		lex.popFront;
		auto tok = lex.expect("(", Tok.EndOfInput);

		if (tok != Tok.EndOfInput) {
			auto argList = parseArgList(lex, false);
			if (pdef.args.length < argList.args.length)
				throw new ParserException(concat("too many parameters for macro '", pdef.pretty(name), "'"), context);

			auto argsSaved = args;
			args = null;

			foreach(i, arg; argList.args)
				args[pdef.args[i]] = expandArg(arg, context);

			// empty out remaining optional parameters
			foreach(i, arg; pdef.args[argList.args.length..$])
				args[arg] = "";

			auto result = processString(pdef.sourceName, pdef.line, pdef.value);
			args = argsSaved;

			return result;
		} else {
			return processString(pdef.sourceName, pdef.line, pdef.value);
		}
	}


	auto parseArgList(ref Lexer lex, bool decl) {
		struct ArgList {
			string[] args;
			Tok[] types;
		}

		assert(lex.value == "(");
		lex.popFront;

		ArgList argList;

		auto tok = decl ? lex.expect(")", Tok.Identifier) : lex.expect(")", Tok.Identifier, Tok.Literal);
		if (lex.value != ")") {
			while (true) {
				argList.args ~= lex.value;
				argList.types ~= tok;

				lex.popFront;
				tok = lex.expect(")", ",");
				if (lex.value == ")")
					break;
				lex.popFront;

				tok = decl ? lex.expect(Tok.Identifier) : lex.expect(Tok.Identifier, Tok.Literal);
			}
		}
		lex.popFront;

		return argList;
	}


	auto parseDef(ref Lexer lex, Context context) {
		struct DefDecl {
			string name;
			string value;
			bool inline;

			string[] args;

			string sourceName;
			size_t line;
		}

		assert(lex.value == "def");
		lex.popFront;
		lex.expect(Tok.Identifier);

		DefDecl decl;
		decl.name = lex.value;
		decl.sourceName = context.sourceName;
		decl.line = context.line;
		lex.popFront;
		auto tok = lex.expect("(", ":", Tok.EndOfInput);
		if (tok != Tok.EndOfInput) {
			if (lex.value == "(") {
				auto argList = parseArgList(lex, true);
				decl.args = argList.args;
			}

			if (lex.value == ":") {
				decl.inline = true;
				decl.value = lex.remaining;
				lex.popFront;
			} else {
				lex.expect(Tok.EndOfInput);
			}
		}

		return decl;
	}


	auto replacer(string content, Context context) {
		if (content.length > 0) {
			auto tag = content[0..1];
			switch(tag) {
				case Tag.Include:
					return include(content, context).strip;
				case Tag.Define:
					return define(content, context).strip;
				default:
					assert(0);
			}
		}
		return null;
	}


	auto lineInfo(string sourceName, size_t lineNumber) {
		if (options.lines)
			return concat("{{", cast(string)Tag.LineInfo, "#line ", lineNumber, " ", sourceName.quoted, "}}");
		return null;
	}


	static auto getFileContents(string fileName, string[] search, bool binary = false) {
		struct Contents {
			string fileName;
			string content;
		}

		Throwable error;
		try {
			if (!binary) {
				return Contents(fileName, (cast(string)read(fileName)).stripUTFbyteOrderMarker);
			} else {
				return Contents(fileName, cast(string)read(fileName));
			}
		} catch(Throwable e) {
			error = e;
		}

		foreach(path; search) {
			auto name = buildNormalizedPath(path, fileName);
			try {
				if (!binary) {
					return Contents(name, (cast(string)read(name)).stripUTFbyteOrderMarker);
				} else {
					return Contents(name, cast(string)read(name));
				}
			} catch(Throwable) {
			}
		}

		throw error;
	}

private:
	struct Def {
		enum Flags : uint {
			NotYetDefined   = 1 << 0,
			Inline          = 1 << 1,
		}

		string value;
		string[] args;
		uint flags;

		string sourceName;
		size_t line;

		string pretty(string name) {
			Appender!string app;
			app.reserve(1024);

			app.put(name);

			app.put("(");

			foreach(i, arg; args) {
				app.put(arg);
				if (i != args.length - 1)
					app.put(", ");
			}
			app.put(")");

			return app.data;
		}
	}

	Options options;
	Def[string] defs;
	string[string] args;
	string[string] deps;

	Context[] contextStack;
}


private @property bool isAllWhite(Range)(Range range) {
	foreach(ch; range) {
		if (!std.uni.isWhite(ch))
			return false;
	}
	return true;
}
