/**
	Allows command line arguments to be mapped to a function using the types passed using the Commander mixin.
*/
module ctoptions.commander;

struct CommandHelp
{
	string value;
	string[] argDocs;
}

struct CommandName
{
	string[] alternateNames;
}

///
mixin template Commander(string modName = __MODULE__)
{
	import std.traits, std.conv, std.stdio, std.typetuple, std.string, std.meta;
	/**
		Handles commands sent via the commandline.

		Examples:
			void create(const string language, generator)
			{
				DoStuff(language, generator);
			}

			void main(string[] arguments)
			{
				mixin Commander;
				Commander commands;
				commands.process(arguments);
			}

			prompt>skeletor create d raijin
	*/
	struct Commander
	{
		private auto getAttribute(alias mem, T)()
		{
			foreach(attr; __traits(getAttributes, mem))
			{
				static if(is(typeof(attr) == T))
				{
					return attr;
				}
			}

			assert(0);
		}

		private void processHelp(alias member)(string memberName, string[] args)
		{
			if(args.length)
			{
				writef("Usage: %s", memberName);

				foreach(argName; ParameterIdentifierTuple!member)
				{
					writef(" <%s>", argName);
				}

				writefln("\n\t%s", getAttribute!(member, CommandHelp).value);

				if(Parameters!member.length)
				{
					writeln("Arguments:");
				}

				auto argDocs = getAttribute!(member, CommandHelp).argDocs;

				foreach(idx, argName; ParameterIdentifierTuple!member)
				{
					string defaultValue;
					bool hasDefaultValue;

					static if(!is(ParameterDefaults!member[idx] == void))
					{
						defaultValue = to!string(ParameterDefaults!member[idx]);
						hasDefaultValue = true;
					}

					string argDoc;

					if(idx < argDocs.length)
					{
						argDoc = argDocs[idx];
					}

					if(argDoc.length)
					{
						writefln("\t%s (%s): %s %s", argName, Parameters!member[idx].stringof, argDoc,
							hasDefaultValue ? "[default=" ~ defaultValue ~ "]" : "");
					}
					else
					{
						writefln("\t%s (%s) %s", argName, Parameters!member[idx].stringof,
							hasDefaultValue ? ": [default=" ~ defaultValue ~ "]" : "");
					}
				}
			}
			else
			{
				writefln("%16s - %s", memberName, getAttribute!(member, CommandHelp).value);
			}
		}

		private void processCommand(alias member)(string memberName, string[] args)
		{
			Parameters!member params;
			alias argumentNames = ParameterIdentifierTuple!member;
			alias defaultArguments = ParameterDefaults!member;

			try
			{
				foreach(idx, ref arg; params)
				{
					if(idx < args.length)
					{
						try
						{
							arg = to!(typeof(arg))(args[idx]);
						}
						catch(ConvException ex)
						{
							writeln(ex.msg);
							writeln("See help ", memberName, " for correct usage.");
						}
					}
					else
					{
						static if(!is(defaultArguments[idx] == void))
						{
							arg = defaultArguments[idx];
						}
						else
						{
							throw new Exception("Required argument, " ~ argumentNames[idx] ~ "(" ~ typeof(arg).stringof ~ ")," ~ " is missing.");
						}
					}
				}

				static if(is(ReturnType!member == void))
				{
					member(params);
				}
				else
				{ //TODO:  Perhaps Add support for returning the result later.
					debug writeln(to!string(member(params)));
				}
			}
			catch(Exception e)
			{
				stderr.writefln(e.msg);
			}
		}

		/**
			Handles processing of commands sent from the commandline.

			Params:
				arguments = The arguments sent from the commandline.

			Returns:
				A true value if command/helpoption was found and its required arguments were found. Note that no
				arguments will also return a true value and should be checked in user's program. False otherwise.
		*/
		void process()(string[] arguments)
		{
			string command;
			string[] args = arguments[1 .. $];
			bool headerShown;
			bool commandFound;
			bool helpCommandFound;

			if(args.length)
			{
				command = args[0];
				args = args[1 .. $];
			}

			alias mod = Alias!(mixin(modName));

			foreach(memberName; __traits(allMembers, mod))
			{
				alias member = Alias!(__traits(getMember, mod, memberName));

				static if(is(typeof(member) == function) && hasUDA!(member, CommandHelp))
				{
					import std.algorithm.mutation : stripLeft;

					if(command.stripLeft('-') == "help")
					{
						commandFound = true;

						if(args.length)
						{
							if(memberName == args[0])
							{
								helpCommandFound = true;

								foreach(overload; __traits(getOverloads, mod, memberName))
								{
									writeln;
									processHelp!overload(memberName, args);
								}
							}
						}
						else
						{
							if(!headerShown)
							{
								writeln("The following options are available:");
								writeln("For additional help use help <command>.");
								writeln;
							}

							processHelp!member(memberName, args);
							headerShown = true;
						}
					}
					else
					{
						string commandNameValue;
						// Set to true or an Invalid arugument will be thrown. Since D has no compile time variables.
						helpCommandFound = true;

						static if(hasUDA!(member, CommandName))
						{
							auto altNames = getAttribute!(member, CommandName).alternateNames;
							foreach(altName; altNames)
							{
								if(altName == command)
								{
									commandNameValue = command;
								}
							}
						}

						if(memberName == command || commandNameValue == command)
						{
							bool found;
							commandFound = true;

							foreach(overload; __traits(getOverloads, mod, memberName))
							{
								immutable Parameters!overload overLoadedParams;

								if(overLoadedParams.length == args.length)
								{
									found = true;
									processCommand!overload(memberName, args);
								}
							}

							if(!found)
							{
								processCommand!member(memberName, args);
							}
						}
					}
				}
			}

			if(!commandFound)
			{
				writeln("Command not found! Use 'help' for a list of commands");
			}

			if(!helpCommandFound && args.length)
			{
				writeln("Invalid argument: ", args[0], ". For a list of commands use help <command>");
			}
		}
	}
}
