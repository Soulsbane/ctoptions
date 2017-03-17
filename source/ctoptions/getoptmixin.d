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

alias GetOptDescription = GetOptOptions;

//FIXME: According to what I've read only the enum <name> part is needed; but it fails unless it's assigned a value.
enum GetOptRequired = "GetOptRequired";
enum GetOptPassThru = "GetOptPassThru";
enum GetOptStopOnFirst = "GetOptStopOnFirst";
enum GetOptBundling = "GetOptBundling";
enum GetOptCaseSensitive = "GetOptCaseSensitive";
//TODO: Add support for other getopt options: http://dlang.org/phobos/std_getopt.html#.config

alias CustomHelpFunction = void function(string text, Option[] opt);

mixin template GetOptMixin(T)
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

	string wrapped()
	{
		static if(hasUDA!(T, GetOptPassThru))
		{
			string getOptCode = "auto helpInformation = getopt(arguments, std.getopt.config.passThrough, ";
		}
		else
		{
			string getOptCode = "auto helpInformation = getopt(arguments, ";
		}

		static if(hasUDA!(T, GetOptStopOnFirst))
		{
			getOptCode ~= "std.getopt.config.stopOnFirstNonOption,";
		}

		static if(hasUDA!(T, GetOptBundling))
		{
			getOptCode ~= "std.getopt.config.bundling,";
		}

		foreach(field; __traits(allMembers, T))
		{
			static if(hasUDA!(mixin("options." ~ field), GetOptOptions))
			{
				auto attr = getUDAs!(mixin("options." ~ field), GetOptOptions);
				string shortName = attr[0].shortName;
				string name = attr[0].name;

				static if(hasUDA!(mixin("options." ~ field), GetOptCaseSensitive))
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
					static if(hasUDA!(mixin("options." ~ field), GetOptRequired))
					{
						getOptCode ~= format(q{
							std.getopt.config.required, "%s%s", "%s", &options.%s,
						}, name, shortName, attr[0].description, field);
					}
					else
					{
						getOptCode ~= format(q{
							"%s%s", "%s", &options.%s,
						}, name, shortName, attr[0].description, field);
					}
				}
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

	mixin(wrapped);
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
bool generateGetOptCode(T)(string[] arguments, ref T options, CustomHelpFunction func = &defaultGetoptPrinter)
{
	try
	{
		///INFO: The options parameter is used in a string mixin with this call.
		mixin GetOptMixin!T;

		if(helpInformation.helpWanted)
		{
			func("The following options are available:", helpInformation.options);
		}

		return helpInformation.helpWanted;
	}
	catch(GetOptException ex)
	{
		writeln(ex.msg);
		writeln("For a list of available commands use --help.");

		return true;
	}
	catch(ConvException ex)
	{
		writeln(ex.msg);
		return true;
	}

	assert(0);
}
