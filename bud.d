#!/usr/bin/env rund
//!importPath src
//!importPath ../rund/src
module __none;

import core.stdc.stdlib : exit;
import std.exception : assumeUnique;
import std.algorithm : canFind;
import std.array;
import std.format;
import std.path;
import std.file;
import std.process;

import bud.log;
import bud.modinfo;

void usage()
{
    logf("Usage: bud [-options] <module-or-package>...");
    logf("Options");
    logf("  -v | --verbose");
}

int main(string[] args)
{
    args = args[1 .. $];

    {
        auto newArgsLength = 0;
        scope (exit) args.length = newArgsLength;
        for (size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if (arg[0] != '-')
            {
                args.ptr[newArgsLength++] = arg;
            }
            else if (arg == "-v" || arg == "--verbose")
                verboseEnabled = true;
            else
            {
                errorf("unknown option '%s'", arg);
                return 1;
            }
        }
    }

    if (args.length == 0)
    {
        usage();
        return 1;
    }

    foreach (arg; args)
    {
        uint attributes;
        try
        {
            attributes = Loggy.getAttributes(arg);
        }
        catch (FileException e)
        {
            errorf("'%s' does not exist", arg);
            return 1;
        }
        if (attrIsFile(attributes))
            buildModule(arg);
        else if (attrIsDir(attributes))
            buildPackage(arg);
        else
        {
            errorf("'%s' exists but is not a file or directory", arg);
            return 1;
        }
    }
    return 0;
}

auto getRelevantEnv()
{
    static __gshared string[string] relevantEnv;
    static bool initialized = false;
    if (!initialized)
    {
        relevantEnv["PATH"] = environment.get("PATH", null);
        initialized = true;
    }
    return relevantEnv;
}

string asShellCommand(string[] command)
{
    auto bufferSize = 0;
    foreach (arg; command)
    {
        if (bufferSize > 0)
            bufferSize += 1; // 1 for space
        bufferSize += arg.length + 2; // 2 for quotes (if needed)
    }
    auto cmd = new char[bufferSize];
    auto cmdSize = 0;
    foreach (arg; command)
    {
        if (cmdSize > 0)
            cmd[cmdSize++] = ' ';
        bool needQuotes = canFind(arg, ' ');
        if (needQuotes)
            cmd[cmdSize++] = '"';
        cmd[cmdSize .. cmdSize + arg.length] = arg[];
        cmdSize += arg.length;
        if (needQuotes)
            cmd[cmdSize++] = '"';
    }
    assert(cmdSize <= bufferSize, "codebug");
    return cmd[0 .. cmdSize].assumeUnique;
}

int tryRun(string[] command)
{
    import std.stdio;
    writefln("[SHELL] %s", asShellCommand(command));
    auto result = spawnProcess(command, stdin, stdout, stderr, getRelevantEnv(), Config.newEnv);
    return wait(result);
}
void run(string[] command)
{
    auto result = tryRun(command);
    if (result != 0)
    {
        errorf("last command exited with code %s", result);
        exit(result);
    }
}


void buildModule(string filename)
{
    auto moduleTypeInfo = readModuleTypeInfo(filename);
    if (moduleTypeInfo.failed)
    {
        errorf("failed determine module type of '%s': %s", filename, moduleTypeInfo.errorMessage);
        exit(1);
    }
    verbosef("%s: module type is '%s'", filename, moduleTypeInfo.typeInfo.type);
    final switch (moduleTypeInfo.typeInfo.type)
    {
    case ModuleType.entry:
        buildEntryModule(filename, moduleTypeInfo.typeInfo.compilerArgs);
        break;
    case ModuleType.package_:
        buildPackageModule(filename, moduleTypeInfo.typeInfo.compilerArgs, moduleTypeInfo.typeInfo.moduleName);
        break;
    }
}
void buildEntryModule(string filename, string[] compilerArgs)
{
    verbosef("buildEntryModule '%s'", filename);

    auto sourceDir = filename.dirName;
    auto binDir = buildPath(sourceDir, "bin");

    verbosef("bin directory '%s'", binDir);
    if (!Loggy.exists(binDir))
        Loggy.mkdir(binDir);

    // TODO: get compiler environment hash
    string envHash = "f64c2f5b7f68396dd721a95e7f3074690910b6d0"; // placeholder value

    auto envDir = buildPath(binDir, envHash);
    if (!Loggy.exists(envDir))
        Loggy.mkdir(envDir);


    auto exeBaseName = baseName(filename).stripExtension;
    auto exe = buildPath(envDir, exeBaseName);
    auto lastBuildJson = buildPath(envDir, "lastBuild.json");
    if (Loggy.exists(lastBuildJson))
    {
        // check if we need to do a rebuild
        errorf("check if rebuild is needed, not implemented");
        //exit(1);
    }

    // if we get here, we need to build
    auto objDir = buildPath(envDir, "obj");
    if (!Loggy.exists(objDir))
        Loggy.mkdir(objDir);

    // for now we'll assume the dmd compiler
    verbosef("compiler args from source directives: %s", compilerArgs);

    auto command = appender!(string[]);
    command.put("dmd");
    command.put("-of=" ~ exe);
    command.put("-od=" ~ objDir);
    command.put("-op");
    command.put("-i");
    command.put("-Xf=" ~ lastBuildJson);
    command.put("-Xi=compilerInfo");
    command.put("-Xi=buildInfo");
    command.put("-Xi=semantics");
    // TODO: verify the compiler args don't conflict and aren't duplicated
    command.put(compilerArgs);
    command.put(filename);
    run(command.data);

    // TODO: make this step optional with the command line
    auto linkName = buildPath(binDir, exeBaseName);
    if (Loggy.exists(linkName))
        Loggy.remove(linkName);
    Loggy.symlink(buildPath(envHash, exeBaseName), linkName);

    // TODO: if the user wanted to run the command, do it here
}

void buildPackageModule(string filename, string[] compilerArgs, string moduleName)
{
    verbosef("buildPackageModule %s '%s'", moduleName, filename);
    errorf("not impl");
    exit(1);
}

void buildPackage(string name)
{
    errorf("buildPackage '%s' not impl", name);
    exit(1);
}