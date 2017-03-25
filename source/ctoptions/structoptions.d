/**
	A key value configuration format using compile time reflection and structs.
*/
module ctoptions.structoptions;

import std.traits;
import std.typecons;
import std.typetuple;
import std.conv;
import std.string;
import std.file;
import std.algorithm;
import std.array;
import std.getopt;
import std.stdio;
import std.string;

private enum DEFAULT_CONFIG_FILE_NAME = "app.config";

/**
	Used for the creation of key/value configuration format.
*/
struct StructOptions(T)
{
	~this() @safe
	{
		if(autoSave_)
		{
			save();
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
	bool loadFile(const string fileName = DEFAULT_CONFIG_FILE_NAME, const bool autoSave = true) @safe
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
		Saves config values to the config file to fileName.

		Params:
			fileName = The name of the file to save to.
	*/
	void save(const string fileName) @safe
	{
		configFileName_ = fileName;
		save();
	}

	/**
		Saves config values to the config file.
	*/
	void save() @safe
	{
		if(configFileName_.length)
		{
			auto configFile = File(configFileName_, "w+");
			string keyValueData;

			foreach(field; __traits(allMembers, T))
			{
				keyValueData ~= field ~ " = " ~ mixin("to!string(data_." ~ field ~ ")") ~ "\n";
			}

			configFile.write(keyValueData);
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
	S as(S, alias key)(const S defaultValue = S.init) pure @safe
	{
		S value = defaultValue;

		try
		{
			immutable string generatedCode = "value = data_." ~ key ~ ".to!S;";
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
	void set(S)(const string key, const S value) pure @safe
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

	void opIndexAssign(T)(T value, const string key) pure @safe
	{
		set(key, value);
	}

	alias data_ this;

	mixin(generateAsMethod!long("asInteger"));
	mixin(generateAsMethod!double("asDecimal"));
	mixin(generateAsMethod!string("asString"));
	mixin(generateAsMethod!bool("asBoolean"));
	alias get = as;

	mixin(generateMethodNameCode!T());

	T data_;

private:
	string configFileName_;
	bool autoSave_;
}

private string generateAsMethod(T)(const string name) pure @safe
{
	return format(q{
		%s %s(alias key)(const %s defaultValue = %s.init) pure @safe
		{
			return as!(%s, key)(defaultValue);
		}
	}, T.stringof, name, T.stringof, T.stringof, T.stringof);
}

private string generateMethodNameCode(T)()
{
	string code;

	foreach (i, memberType; typeof(T.tupleof))
	{
		code ~= format(q{
			%s get%s(const %s defaultValue = %s.init) pure @safe
			{
				return as!(%s, "%s")(defaultValue);
			}
		}, memberType.stringof, T.tupleof[i].stringof.capitalize, memberType.stringof, memberType.stringof, memberType.stringof, T.tupleof[i].stringof);
	}

	return code;
}

///
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
	assert(options.asInteger!("id")(10) == 50);
	assert(options.asInteger!("id") == 50);
	assert(options.asString!("id") == "50");

	//Sugar
	assert(options.getId(10) == 50); // TODO: Make this work!
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
	assert(options.loadString(emptyData) == false);
	writeln(generateMethodNameCode!VariedData());
}
