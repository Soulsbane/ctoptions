/**
	Enables the autogeneration of getopt commandline parameters based on a passed structs members.
*/
module ctoptions.getoptmixin;

public import std.getopt;
public import std.typecons;

import std.traits;
import std.stdio;
import std.format;
import std.string;
import std.range;
import std.conv;
import std.functional;

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
	string object;
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

	struct GetOptMixinStringGenerator
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
				immutable string objectName = attrValues.object;
				string callback;

				if(objectName.length)
				{
					callback = objectName ~ "." ~ callbackFuncName;
				}
				else
				{
					callback = modName ~ "." ~ callbackFuncName;
				}

				static if(hasUDA!(mixin("T." ~ field), GetOptCaseSensitive))
				{
					getOptCode ~= "std.getopt.config.caseSensitive,";
				}

				static if(hasUDA!(mixin("T." ~ field), GetOptRequired))
				{
					getOptCode ~= format(q{
						std.getopt.config.required, "%s", &%s,
					}, commandLineName, callback);
				}
				else
				{
					getOptCode ~= format(q{ "%s", &%s, }, commandLineName, callback);
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
					immutable string objectName = attrValues.object;
					string callback;

					if(objectName.length)
					{
						callback = objectName ~ "." ~ callbackFuncName;
					}
					else
					{
						callback = modName ~ "." ~ callbackFuncName;
					}

					static if(hasUDA!(T, GetOptCaseSensitive))
					{
						getOptCode ~= "std.getopt.config.caseSensitive,";
					}

					static if(hasUDA!(T, GetOptRequired))
					{
						getOptCode ~= format(q{
							std.getopt.config.required, "%s", &%s,
						}, commandLineName, callback);
					}
					else
					{
						getOptCode ~= format(q{ "%s", &%s, }, commandLineName, callback);
					}
				}
			}

			return getOptCode;
		}
	}

	string createGetOptMixinString()
	{
		string getOptCode = GetOptMixinStringGenerator.generateGlobalOptions();
		getOptCode ~= GetOptMixinStringGenerator.generateTopLevelCallbacks();

		foreach(field; __traits(allMembers, T))
		{
			static if(hasUDA!(mixin("T." ~ field), GetOptOptions))
			{
				getOptCode ~= GetOptMixinStringGenerator.generateOptions!field;
			}
			static if(hasUDA!(mixin("T." ~ field), GetOptCallback))
			{
				getOptCode ~= GetOptMixinStringGenerator.generateCallbacks!field;
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

/**
	Generates generic code for use in std.getopt.

	Params:
		arguments = The arguments sent from the command-line
		options = The struct that will be used to generate getopt options from.
		func = The function to call when --help is passed. defaultGetoptPrinter by default.

	Returns:
		A string containing the error text.

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
string generateGetOptCode(T, string varName = "options", string modName = __MODULE__)
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
		immutable string message = parseErrorText(ex.msg ~ ". For a list of available commands use --help.");
		return message;
	}
	catch(ConvException ex)
	{
		immutable string message = parseErrorText(ex.msg);
		return message;
	}
	catch(Exception ex)
	{
		immutable string message = parseErrorText(ex.msg);
		return message;
	}

	return string.init;
}

// TODO: Better parsing especially when there is a type mismatch
string parseErrorText(const string exceptionText)
{
	import std.algorithm : splitter;

	immutable auto lines = splitter(exceptionText, "\n").array;

	if(lines.length >= 1)
	{
		return lines[0];
	}

	return string.init;
}

private string generateHasMethodNameCode(T)()
{
	string code;

	foreach (i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			bool has%s(const %s value) const pure nothrow @safe
			{
				if(getOptOptions_.%s == value)
				{
					return true;
				}

				return false;
			}
		}, memNameCapitalized, memType, memName);

		code ~= format(q{
			bool has%s() const pure nothrow @safe
			{
				if(getOptOptions_.%s == %s.init)
				{
					return false;
				}

				return true;
			}
		}, memNameCapitalized, memName, memType);
	}

	return code;
}

private string generateGetMethodNameCode(T)()
{
	string code;

	foreach (i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			%s get%s(const %s defaultValue = %s.init) @safe
			{
				if(defaultValue != %s.init)
				{
					return getOptOptions_.%s;
				}

				return defaultValue;
			}
		}, memType, memNameCapitalized, memType, memType, memType, memName);
	}

	return code;
}

class GetOptCodeGenerator(T, const Flag!"generateHelperMethods" generateHelperMethods = Yes.generateHelperMethods,
string modName = __MODULE__)
{
	static if(generateHelperMethods == Yes.generateHelperMethods)
	{
		mixin(generateHasMethodNameCode!T);
		mixin(generateGetMethodNameCode!T);
	}

	void generate(string[] arguments, ref T options, CustomHelpFunction func = &defaultGetoptPrinter)
	{
		/*debug // This is temporary so we can check the generated code.
		{
			import std.stdio : writeln;
			writeln(generateHasMethodNameCode!T);
			writeln(generateGetMethodNameCode!T);
		}*/

		try
		{
			appArguments = arguments;

			if(arguments.length == 1)
			{
				onNoArguments();
			}
			else
			{
				///INFO: The options parameter is used in a string mixin with this call.
				mixin GetOptMixin!(T, "options", modName);
				getOptOptions_ = options;

				if(helpInformation.helpWanted)
				{
					isHelpCommand_ = true;
					onHelp(helpInformation.options);
				}
				else
				{
					onValidArguments();
				}
			}
		}
		catch(GetOptException ex) // Called when arg is missing it's value. id=10 but the 10 is left out.
		{
			immutable string message = parseErrorText(ex.msg ~ ". For a list of available commands use --help.");
			onUnknownArgument(message);
		}
		catch(ConvException ex) // Called when argument is passed a wrong type. int id; --id=hi
		{
			immutable string message = parseErrorText(ex.msg ~ ". For a list of available commands use --help.");
			onInvalidArgument(message);
		}
		catch(Exception ex)
		{
			immutable string message = parseErrorText(ex.msg ~ ". For a list of available commands use --help.");
			onInvalidArgument(message);
		}
	}

	string[] getArgumentsRaw()
	{
		return appArguments;
	}

	bool isHelpCommand() const pure nothrow @safe
	{
		return isHelpCommand_;
	}

	/**
		Called when no arguments are passed to the command line.
	*/
	void onNoArguments() { }

	/**
		Called when --help is passed to the command line.
	*/
	void onHelp(Option[] options)
	{
		defaultGetoptPrinter("The following options are available:", options);
	}

	/**
		Called when all arguments containing no errors are passed to the command line.
	*/
	void onValidArguments() {}

	/**
		Called when an argument is missing it's value. Example: <applicationName> --id=10 but the 10 is left out.
	*/
	void onUnknownArgument(const string msg)
	{
		writeln(msg);
	}
	/**
		Called when an argument is passed a wrong type. Example: int id; --id=hello
	*/
	void onInvalidArgument(const string msg)
	{
		writeln("Invalid Argument!");
		writeln(msg);
	}

private:
	T getOptOptions_;
	string[] appArguments;
	bool isHelpCommand_;
}
