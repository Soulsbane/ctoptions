/**
	A key value configuration format using compile time reflection and structs.
*/
module ctoptions.structoptions;

import std.traits : isFloatingPoint;
import std.traits, std.typecons, std.typetuple, std.conv;
import std.string, std.file, std.algorithm, std.array;
import std.getopt, std.stdio, std.string, std.uni, std.math;

private enum DEFAULT_CONFIG_FILE_NAME = "app.config";
enum DisableSave; // UDA to disable the saving of members to file.

/**
	Used for the creation of key/value configuration format.
*/
struct StructOptions(T)
{
	this(T)(T values)
	{
		string code;

		foreach (i, memberType; typeof(T.tupleof))
		{
			immutable string memName = T.tupleof[i].stringof;

			code ~= format(q{
				if(values.%s != data_.%s && values.%s != values.%s.init)
				{
					data_.%s = values.%s;
				}
			}, memName, memName, memName, memName, memName, memName);
		}
	}

	/**
		Loads a config fileName(app.config by default).

		Params:
			fileName = The name of the file to be processed/loaded. Will use app.config if no argument is passed.
			autoSave = Enable saving on object destruction. Set to true by default.

		Returns:
			Returns true on a successful load false otherwise.
	*/
	bool loadFile(const string fileName = DEFAULT_CONFIG_FILE_NAME) @safe
	{
		if(fileName.exists)
		{
			configFileName_ = fileName;
			return loadString(fileName.readText);
		}

		return false;
	}

	/**
		Similar to loadFile but loads and processes the passed string instead.

		Params:
			text = The string to process.

		Returns:
			Returns true on a successful load false otherwise.
	*/
	bool loadString(const string text) @safe
	{
		if(text.length)
		{
			auto lines = text.lineSplitter().array;

			foreach(line; lines)
			{
				auto keyAndValue = line.findSplit("=");
				immutable string key = keyAndValue[0].strip();
				immutable string value = keyAndValue[2].strip();

				if(keyAndValue[1].length)
				{
					foreach(field; __traits(allMembers, T))
					{
						if(field == key)
						{
							// This generates code in the form of: data_.field=to!type(value);
							immutable string generatedCode = "data_." ~ field ~ "=to!" ~ typeof(mixin("data_." ~ field))
								.stringof ~ "(value);";

							mixin(generatedCode);
						}
					}
				}
			}

			return true;
		}

		return false;
	}

	/**
		Saves config values to the specified config file name.
	*/
	void save(const string fileName = DEFAULT_CONFIG_FILE_NAME) @safe
	{
		configFileName_ = fileName;

		auto configFile = File(configFileName_, "w+");
		string keyValueData;

		foreach(field; __traits(allMembers, T))
		{
			static if(!hasUDA!(mixin("T." ~ field), DisableSave))
			{
				immutable string strType = typeof(mixin("T." ~ field)).stringof;

				static if(mixin("isFloatingPoint!" ~ strType))
				{
					if(mixin("isNaN(data_." ~ field ~ ")"))
					{
						keyValueData ~= field ~ " = 0.0\n";
					}
					else
					{
						keyValueData ~= field ~ " = " ~ mixin("to!string(data_." ~ field ~ ")") ~ "\n";
					}
				}
				else
				{
					keyValueData ~= field ~ " = " ~ mixin("to!string(data_." ~ field ~ ")") ~ "\n";
				}
			}
		}

		configFile.write(keyValueData);
	}

	/**
		Creates a config file containing default values of passed struct.

		Params:
			fileName = The name of the file to save to.
			forceRecreate = Remove old config file and replace it with a new one.
	*/
	void createDefaultFile(const string fileName, const bool forceRecreate = false)
	{
		// FIXME: Find a better way to do this when I'm more rested!
		if(!fileName.exists || forceRecreate)
		{
			if(fileName.exists)
			{
				fileName.remove();
			}

			save(fileName);
		}
	}

	/**
		Retrieves the value  associated with key where T is the designated type to be converted to.

		Params:
			key = Name of the key to get.
			defaultValue = The defaultValue to use should the key not exist.

		Returns:
			The value associated with key.
	*/
	S as(S, alias key)(const S defaultValue = S.init) //pure @safe
	{
		S value = defaultValue;

		try
		{
			immutable string generatedCode = format(q{
				if(data_.%s.to!S != S.init)
				{
					value = data_.%s.to!S;
				}
			}, key, key);

			mixin(generatedCode);
		}
		catch(ConvException ex)
		{
			return defaultValue;
		}

		return value;
	}

	/**
		Sets a config value.

		Params:
			key = Name of the key to set.
			value = The value of key.
	*/
	void set(S)(const string key, const S value) @safe
	{
		foreach(field; __traits(allMembers, T))
		{
			if(field == key)
			{
				immutable string generatedCode = "data_." ~ field ~ " = value.to!" ~ typeof(mixin("data_." ~ field))
					.stringof ~ ";";

				mixin(generatedCode);
			}
		}
	}

	/**
		Determines if the key is found in the config file.

		Params:
			key = Name of the key to get the value of

		Returns:
			true if the config file contains the key false otherwise.
	*/
	bool contains(const string key) const pure @safe
	{
		foreach(field; __traits(allMembers, T))
		{
			if(field == key)
			{
				return true;
			}
		}

		return false;
	}

	void opIndexAssign(T)(T value, const string key) @safe
	{
		set(key, value);
	}

	alias data_ this;

	mixin(generateAsMethod!long("asInteger"));
	mixin(generateAsMethod!double("asDecimal"));
	mixin(generateAsMethod!string("asString"));
	mixin(generateAsMethod!bool("asBoolean"));
	alias get = as;

	mixin(generateAsMethodNameCode!T());
	mixin(generateSetMethodNameCode!T());
	mixin(generateHasMethodNameCode!T);

	T data_;

private:
	string configFileName_;
	bool autoSave_;
}

/*
	This generates an accessor function based on the name and type passed.
	For example:

	mixin(generateAsMethod!long("asInteger"));

	will generate this code:

	long asInteger(alias key)(const long defaultValue = long.init) pure @safe
	{
		return as!(long, key)(defaultValue);
	}
*/
private string generateAsMethod(T)(const string name) pure @safe
{
	return format(q{
		%s %s(alias key)(const %s defaultValue = %s.init) pure @safe
		{
			return as!(%s, key)(defaultValue);
		}
	}, T.stringof, name, T.stringof, T.stringof, T.stringof);
}

/*
	This generates an accessor method based on a structs member names. For example this struct:

	struct Test
	{
		string name;
	}

	will generate this code:

	string getName(const string defaultValue = string.init) pure @safe
	{
		return as!(string, "name")(defaultValue);
	}

	it does this for each member of the struct.
*/
private string generateAsMethodNameCode(T)()
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
				return as!(%s, "%s")(defaultValue);
			}
		}, memType, memNameCapitalized, memType, memType, memType, memName);
	}

	return code;
}

/**
	This generates an accessor method based on a structs member names.
	For example this struct:

	struct Foo
	{
		size_t id;
	}

	will generate this code:

	bool hasId(const ulong value = ulong.init) const pure nothrow @safe
	{
		if(data_.id == value)
		{
			return true;
		}

		return false;
	}

	bool hasId() const pure nothrow @safe
	{
		if(data_.id != size_t.init)
		{
			return true;
		}

		return false;
	}

	it does this for each member of the struct.
*/
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
				if(data_.%s == value)
				{
					return true;
				}

				return false;
			}
		}, memNameCapitalized, memType, memName);

		code ~= format(q{
			bool has%s() const pure nothrow @safe
			{
				if(data_.%s == %s.init)
				{
					return false;
				}

				return true;
			}
		}, memNameCapitalized, memName, memType);
	}

	return code;
}

/*
	This generates an set method based on a structs member names. For example this struct:

	struct Test
	{
		string name;
	}

	will generate this code:

	void setName(const string value) pure @safe
	{
		return set("name", value);
	}

	it does this for each member of the struct.
*/
private string generateSetMethodNameCode(T)()
{
	string code;

	foreach (i, memberType; typeof(T.tupleof))
	{
		immutable string memType = memberType.stringof;
		immutable string memName = T.tupleof[i].stringof;
		immutable string memNameCapitalized = memName[0].toUpper.to!string ~ memName[1..$];

		code ~= format(q{
			void set%s(const %s value) @safe
			{
				return set("%s", value);
			}
		}, memNameCapitalized, memType, memName);
	}

	return code;
}

///
@("StructOptions")
unittest
{
	struct VariedData
	{
		string name;
		size_t id;
	}

	immutable string data =
	q{
			name = Paul
			id = 50
	};

	StructOptions!VariedData options;
	options.loadString(data);

	assert(options.as!(string, "name")("onamae") == "Paul");
	assert(options.as!(string, "name") == "Paul"); // No default value passed.

	assert(options.contains("id"));
	assert(options.contains("nothing") == false);

	assert(options.asInteger!("id")(10) == 50);
	assert(options.asInteger!("id") == 50);
	assert(options.asString!("id") == "50");

	//Sugar
	assert(options.hasId(50) == true);
	assert(options.getId(10) == 50);
	assert(options.getName() == "Paul");

	assert(options.contains("invalid") == false);

	assert(options.name == "Paul");

	options.name = "Bob";
	assert(options.name == "Bob");

	options.set("name", "Kyle");
	assert(options.name == "Kyle");

	options["name"] = "Jim";
	assert(options.name == "Jim");

	assert(options.as!(long, "id")(1) == 50);

	immutable string emptyData;

	StructOptions!VariedData dataEmptyOptions;
	assert(dataEmptyOptions.loadString(emptyData) == false);

	immutable string oneValue =
	q{
			name = Paul
	};

	StructOptions!VariedData oneValueTest;

	oneValueTest.loadString(oneValue);
	assert(oneValueTest.getId(10) == 10);

	oneValueTest.setId(5281);
	assert(oneValueTest.getId() == 5281);

	struct IrregularNames
	{
		string tocField;
		size_t id;
	}

	StructOptions!IrregularNames irrNames;

	irrNames.setTocField("Setting toc field");
	irrNames.setId(1900);

	assert(irrNames.getTocField == "Setting toc field");
	assert(irrNames.getId = 1900);

	/*struct Foo
	{
		size_t id;
	}

	writeln(generateHasMethodNameCode!Foo);*/
}
