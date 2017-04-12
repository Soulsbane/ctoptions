/**
	Enables the autogeneration of getopt commandline parameters based on a passed structs members.
*/
module ctoptions.getoptmixin;

import std.getopt;
import std.traits;
import std.stdio;
import std.format;
import std.string;
import std.range;
import std.conv;

///The attribute used for marking members
struct GetOptOptions
{
	string description;
	string shortName;
	string name;
}

struct GetOptCallback
{
	string name;
	string func;
}

alias GetOptDescription = GetOptOptions;

enum GetOptRequired = "GetOptRequired";
enum GetOptPassThru = "GetOptPassThru";
enum GetOptStopOnFirst = "GetOptStopOnFirst";
enum GetOptBundling = "GetOptBundling";
enum GetOptCaseSensitive = "GetOptCaseSensitive";

alias CustomHelpFunction = void function(string text, Option[] opt);

mixin template GetOptMixin(T, string varName = "options", string modName = __MODULE__)
{
	/**
		Using the example struct below this string mixin generates this code.

		struct VariedData
		{
			@GetOptOptions("The name of the program")
			string name;
			@GetOptOptions("The id of the program")
			size_t id;
		}

		//The actual generated string.
		auto helpInformation = getopt(arguments, "name", "The name of the program",
			&options.name, "id", "The id of the program", &options.id);
	*/

	import std.traits, std.format;

	struct GetOptCodeGenerator
	{
		static string generateGlobalOptions()
		{
			static if(hasUDA!(T, GetOptPassThru))
			{
				string getOptCode = "import " ~ modName ~ ";";
				getOptCode ~= "auto helpInformation = getopt(arguments, std.getopt.config.passThrough, ";
			}
			else
			{
				string getOptCode = "import " ~ modName ~ ";";
				getOptCode ~= "auto helpInformation = getopt(arguments, ";
			}

			static if(hasUDA!(T, GetOptStopOnFirst))
			{
				getOptCode ~= "std.getopt.config.stopOnFirstNonOption,";
			}

			static if(hasUDA!(T, GetOptBundling))
			{
				getOptCode ~= "std.getopt.config.bundling,";
			}

			return getOptCode;
		}

		static string generateOptions(alias field)()
		{
			string getOptCode;
			auto attr = getUDAs!(mixin("T." ~ field), GetOptOptions);
			string shortName = attr[0].shortName;
			string name = attr[0].name;

			static if(hasUDA!(mixin("T." ~ field), GetOptCaseSensitive))
			{
				getOptCode ~= "std.getopt.config.caseSensitive,";
			}

			if(shortName.length)
			{
				shortName = "|" ~ shortName;
			}
			else
			{
				shortName = string.init;
			}

			if(!name.length)
			{
				name = field;
			}

			static if(attr.length == 1)
			{
				static if(hasUDA!(mixin("T." ~ field), GetOptRequired))
				{
					getOptCode ~= format(q{
						std.getopt.config.required, "%s%s", "%s", &%s.%s,
					}, name, shortName, attr[0].description, varName, field);
				}
				else
				{
					getOptCode ~= format(q{
						"%s%s", "%s", &%s.%s,
					}, name, shortName, attr[0].description, varName, field);
				}
			}

			return getOptCode;
		}

		static string generateCallbacks(alias field)()
		{
			string getOptCode;

			immutable auto memberCallbackAttributes = getUDAs!(mixin("T." ~ field), GetOptCallback);

			foreach(attrValues; memberCallbackAttributes)
			{
				string commandLineName = attrValues.name;
				immutable string callbackFuncName = attrValues.func;

				static if(hasUDA!(mixin("T." ~ field), GetOptCaseSensitive))
				{
					getOptCode ~= "std.getopt.config.caseSensitive,";
				}

				static if(hasUDA!(mixin("T." ~ field), GetOptRequired))
				{
					getOptCode ~= format(q{
						std.getopt.config.required, "%s", &%s.%s,
					}, commandLineName, modName, callbackFuncName);
				}
				else
				{
					getOptCode ~= format(q{ "%s", &%s.%s, }, commandLineName, modName, callbackFuncName);
				}
			}

			return getOptCode;
		}

		static string generateTopLevelCallbacks()
		{
			string getOptCode;

			static if(hasUDA!(T, GetOptCallback))
			{
				immutable auto callbackAttributes = getUDAs!(T, GetOptCallback);

				foreach(attrValues; callbackAttributes)
				{
					string commandLineName = attrValues.name;
					immutable string callbackFuncName = attrValues.func;

					static if(hasUDA!(T, GetOptCaseSensitive))
					{
						getOptCode ~= "std.getopt.config.caseSensitive,";
					}

					static if(hasUDA!(T, GetOptRequired))
					{
						getOptCode ~= format(q{
							std.getopt.config.required, "%s", &%s.%s,
						}, commandLineName, modName, callbackFuncName);
					}
					else
					{
						getOptCode ~= format(q{ "%s", &%s.%s, }, commandLineName, modName, callbackFuncName);
					}
				}
			}

			return getOptCode;
		}
	}

	string createGetOptMixinString()
	{
		string getOptCode = GetOptCodeGenerator.generateGlobalOptions();
		getOptCode ~= GetOptCodeGenerator.generateTopLevelCallbacks();

		foreach(field; __traits(allMembers, T))
		{
			static if(hasUDA!(mixin("T." ~ field), GetOptOptions))
			{
				getOptCode ~= GetOptCodeGenerator.generateOptions!field;
			}
			static if(hasUDA!(mixin("T." ~ field), GetOptCallback))
			{
				getOptCode ~= GetOptCodeGenerator.generateCallbacks!field;
			}
		}

		getOptCode = getOptCode.stripRight;

		if(getOptCode.back == ',')
		{
			getOptCode.popBack;
			getOptCode ~= ");";
		}

		return getOptCode;
	}

	mixin(createGetOptMixinString);
}

class GetOptMixinException: Exception
{
	public
	{
		@safe pure nothrow this(string message, string file =__FILE__, size_t line = __LINE__, Throwable next = null)
		{
			super(message, file, line, next);
		}
	}
}

/**
	Generates generic code for use in std.getopt.

	Params:
		arguments = The arguments sent from the command-line
		options = The struct that will be used to generate getopt options from.
		func = The function to call when --help is passed. defaultGetoptPrinter by default.

	Examples:
		import std.stdio;

		struct VariedData
		{
			//Sets the description in --help for command and makes this command a std.getopt.command.required argument.
			@GetOptOptions("The name of the program") @GetOptRequired
			string name;
			@GetOptOptions("The id of the program")
			size_t id;
		}

		void main(string[] arguments)
		{
			VariedData data;

			data.name = "Paul Crane";
			data.id = 13;
			generateGetOptCode!VariedData(arguments, data);

			writeln("after data.id => ", data.id);
		}
*/
void generateGetOptCode(T, string varName = "options", string modName = __MODULE__)
	(string[] arguments, ref T options, CustomHelpFunction func = &defaultGetoptPrinter)
{
	try
	{
		///INFO: The options parameter is used in a string mixin with this call.
		mixin GetOptMixin!(T, varName, modName);

		if(helpInformation.helpWanted)
		{
			func("The following options are available:", helpInformation.options);
		}
	}
	catch(GetOptException ex)
	{
		throw new GetOptMixinException(ex.msg, "For a list of available commands use --help.");
	}
	catch(ConvException ex)
	{
		throw new GetOptMixinException(ex.msg);
	}
	catch(Exception ex)
	{
		throw new GetOptMixinException(ex.msg);
	}
}
