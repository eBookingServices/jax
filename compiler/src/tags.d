module tags;


enum Tag : string {
	OpenTag      = "{{",
	CloseTag     = "}}",

	Include      = "&",
	Iterate      = "*",
	Close        = "/",
	If           = "?",
	OrElse       = ":",
	Evaluate     = "%",
	Comment      = "!",
	Define       = "#",
	Translate    = "~",
	LineInfo	 = ";",
}
