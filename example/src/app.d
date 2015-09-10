import std.functional;

import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;

import templ;


version(VibeCustomMain) {
	int main(string[] args) {
		import vibe.core.args : finalizeCommandLineOptions;
		import vibe.core.core : runEventLoop, lowerPrivileges;
		import vibe.core.log;
		import std.encoding : sanitize;

		try {
			if (!finalizeCommandLineOptions())
				return 0;
		} catch (Exception e) {
			return 1;
		}

		serverStart();

		lowerPrivileges();

		try {
			return runEventLoop();
		} catch (Throwable e) {
			logError("Unhandled exception in event loop: %s", e.msg);
			logDiagnostic("Full exception: %s", e.toString().sanitize());
			return 1;
		}
	}
} else {
	shared static this() {
		serverStart();
	}
}


void serverStart() {
	{
		import etc.linux.memoryerror;
		static if (is(typeof(registerMemoryErrorHandler)))
			registerMemoryErrorHandler();
	}

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.errorPageHandler = toDelegate(&handleError);
	listenHTTP(settings, routerSetup);
}


auto routerSetup() {
	return (new URLRouter)
		.get("/", &handleRequest)
		.get("/index.html", &handleRequest);
}


@property void renderTemplate(string FileName, Vars...)(HTTPServerResponse res) {
    if ("Content-Type" !in res.headers)
        res.headers["Content-Type"] = "text/html; charset=UTF-8";

	enum defaultLanguage = "en";

    templ.render!(typeof(res.bodyWriter), FileName, Vars)(res.bodyWriter, defaultLanguage);
}


void handleError(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error) {
	struct TemplData {
		string title;
	}

	TemplData td;
	td.title = "Error";

	res.renderTemplate!("error.html", td, error);
}


void handleRequest(HTTPServerRequest req, HTTPServerResponse res) {
	struct TemplData {
		string title;
		string header;
		string[string] iterable;
	}

	TemplData td;
	td.title = "Content";
	td.header = "This is example content";
	td.iterable["1"] = "The number one";
	td.iterable["2"] = "The number two";
	td.iterable["3"] = "The number three";

	res.renderTemplate!("index.html", td);
}
