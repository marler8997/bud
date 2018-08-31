module bud.log;

import std.format : format;
import std.stdio : writef, writefln, writeln, stderr;

__gshared bool verboseEnabled;

void logf(T...)(string format, T args)
{
    import std.stdio : writefln;
    writefln(format, args);
}
void verbosef(T...)(string format, T args)
{
    if (verboseEnabled)
    {
        import std.stdio : write, writefln;
        write("verbose: ");
        writefln(format, args);
    }
}
void errorf(T...)(string format, T args)
{
    import std.stdio : write, writefln;
    stderr.write("Error: ");
    stderr.writefln(format, args);
}
void warningf(T...)(string format, T args)
{
    import std.stdio : write, writefln;
    stderr.write("Warning: ");
    stderr.writefln(format, args);
}

struct Loggy
{
    static auto getAttributes(R)(R name)
    {
        static import std.file;
        verbosef("getAttributes '%s'", name);
        return std.file.getAttributes(name);
    }

    static auto opDispatch(string func, T...)(T args)
    {
        import std.file;
        import std.algorithm : among;
        import std.string : endsWith;

        static if (func.endsWith("IfLive"))
        {
            enum fileFunc = func[0 .. $ - "IfLive".length];
            enum skipOnDryRun = true;
        }
        else
        {
            enum fileFunc = func;
            enum skipOnDryRun = false;
        }

        static if (fileFunc.among("copy", "moveFile", "rename", "symlink"))
        {
            enum logReturn = false;
            verbosef("%s %s %s", fileFunc, args[0], args[1]);
        }
        else static if (fileFunc.among("remove", "mkdir", "mkdirRecurse", "rmdirRecurse", "dirEntries", "write",
            "writeEmptyFile", "readText", "exists", "timeLastModified", "isFile", "isDir", "existsAsFile", "getFileAttributes",))
        {
            enum logReturn = false;
            verbosef("%s %s", fileFunc, args[0]);
        }
        else static if (fileFunc.among("which"))
        {
            enum logReturn = true;
        }
        else static assert(0, "Filesystem.opDispatch has not implemented " ~ fileFunc);

        static if (skipOnDryRun)
        {
            if (dryRun)
                return;
        }

        static if (logReturn)
        {
            mixin("auto result = " ~ fileFunc ~ "(args);");
            verbosef("%s %s => %s", fileFunc, args[0].formatQuotedIfSpaces, result.formatQuotedIfSpaces);
            return result;
        }
        else
        {
            mixin("return " ~ fileFunc ~ "(args);");
        }
    }
}

