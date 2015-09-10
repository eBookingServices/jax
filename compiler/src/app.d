import std.algorithm;
import std.array;
import std.datetime;
import std.file;
import std.getopt;
import std.path;
import std.stdio;
import std.string;

import compressor;
import parser;
import token;
import utils;


string[] compile(string fileName, string outputDir, bool lineNumbers, bool compress, string[] search) {
	string[] deps;

	auto header = "// DO NOT MODIFY - This file was automatically generated - any changes will be overwritten\n";
	auto source = Parser.compile(fileName, Parser.Options(compress ? CompressOptions.defaults : CompressOptions.none, lineNumbers, search, &deps));
	auto target = buildNormalizedPath(outputDir, concat(fileName, ".d.mixin"));

	if (source.length) {
		// TODO: properly propagate errors to allow empty files
		if (!outputDir.empty) {
			try {
				mkdirRecurse(outputDir);
			} catch(Throwable) {
			}
		}
		std.file.write(target, source);
	} else if (exists(target)) {
		std.file.remove(target);
	}

	return deps;
}


int main(string[] args) {
    auto compress = false;
	auto verbose = false;
	auto depCacheGenOnly = false;
	auto lineNumbers = false;
	auto time = false;
	string tokenArg;
	string outputDir;
	string depCache;
    string[] search;

	try {
		auto opts = getopt(args,
			"o|output-dir",		"Output directory", &outputDir,
			"p|time",			"Display elapsed time at end", &time,
			"v|verbose",		"Verbose output", &verbose,
			"l|line-numbers",	"Keep line numbers for error reporting (disables compression)", &lineNumbers,
			"d|dep-cache",		"Dependant-cache directory", &depCache,
			"g|dep-gen-only",	"Only generate dependant-cache, do not re-compile dependants", &depCacheGenOnly,
			"c|compress",		"Compress HTML in between template tags", &compress,
			"j|search",			"Search path(s) to look for dependency files", &search,
			"t|token",			"Token for token_url interpolation filter. Useful for cache-busting", &tokenArg);

		if (opts.helpWanted || (args.length != 2)) {
			defaultGetoptPrinter("Usage: jax [OPTIONS] FileName\n", opts.options);
			return 1;
		}
	} catch (Exception e) {
		writeln("Error: ", e.msg);
		return 1;
	}

	if (!tokenArg.empty) {
		token.set(tokenArg);
	} else {
		token.randomize();
	}

	if (lineNumbers)
		compress = false;

	if (!outputDir.empty) {
		if (!isAbsolute(outputDir))
			outputDir = absolutePath(outputDir);
	}


    string fileName = args[1];
	if (verbose)
		writeln("Compiling ", fileName, "...");

	auto timeStart = Clock.currTime;

	string[] deps;
	try {
		deps = compile(fileName, outputDir, lineNumbers, compress, search);
	} catch (Exception error) {
		writeln("Error: ", error.msg);
		return 1;
	}

	if (depCache.length) {
		immutable depsExtension = ".deps";

		auto depsFileName = buildNormalizedPath(depCache, concat(fileName, depsExtension));
		try {
			mkdirRecurse(depsFileName.dirName);
		} catch(Throwable) {
		}

		if (!depCacheGenOnly) {
			if (!isAbsolute(depCache))
				depCache = absolutePath(depCache);

			string[] dependants;
			foreach(entry; dirEntries(depCache, SpanMode.breadth)) {
				if (!entry.isDir) {
					if (entry.name.extension == depsExtension) {
						foreach(depName; File(entry.name).byLine) {
							if (depName == fileName)
								dependants ~= relativePath(entry.name[0..$-depsExtension.length], depCache);
						}
					}
				}
			}

			if (dependants.length) {
				foreach(dependant; dependants) {
					if (verbose)
						writeln("Compiling dependant ", dependant, "...");
					try {
						compile(dependant, outputDir, lineNumbers, compress, search);
					} catch (Exception error) {
						writeln("Error: ", error.msg);
					}
				}
			}
		}

		Appender!string appender;
		appender.reserve(8 * 1024);
		foreach(depName; deps.sort().uniq) {
			appender.put(depName);
			appender.put("\n");
		}
		std.file.write(depsFileName, appender.data);
	}

	auto timeEnd = Clock.currTime;
	if (time)
		writeln(format("Total elapsed: %.1fms", (timeEnd - timeStart).total!"usecs" * 0.001f));

    return 0;
}
