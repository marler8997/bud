module bud.modtype;

import std.exception : assumeUnique;

import rund.directives;

import bud.log;

enum ModuleType { entry, package_ }
struct ModuleTypeInfo
{
    ModuleType type;
    string[] compilerArgs; // taken from source directives
    union
    {
        string moduleName;
        // TODO: ass source compiler directives for entry modules
    }
    static ModuleTypeInfo entry(string[] compilerArgs) { return ModuleTypeInfo(ModuleType.entry, compilerArgs); }
    static ModuleTypeInfo package_(string[] compilerArgs, string moduleName)
    {
        return ModuleTypeInfo(ModuleType.package_, compilerArgs, moduleName);
    }
}

struct OptionalModuleTypeInfo
{
    union
    {
        ModuleTypeInfo typeInfo;
        string errorMessage;
    }
    bool failed;
    static OptionalModuleTypeInfo entry(string[] compilerArgs)
    {
        auto typeInfo = OptionalModuleTypeInfo();
        typeInfo.typeInfo = ModuleTypeInfo.entry(compilerArgs);
        typeInfo.failed = false;
        return typeInfo;
    }
    static OptionalModuleTypeInfo package_(string[] compilerArgs, string moduleName)
    {
        auto typeInfo = OptionalModuleTypeInfo();
        typeInfo.typeInfo = ModuleTypeInfo.package_(compilerArgs, moduleName);
        typeInfo.failed = false;
        return typeInfo;
    }
    static OptionalModuleTypeInfo error(string errorMessage)
    {
        auto typeInfo = OptionalModuleTypeInfo();
        typeInfo.errorMessage = errorMessage;
        typeInfo.failed = true;
        return typeInfo;
    }
}

// Assume: file pointing to the beginning of the file

OptionalModuleTypeInfo readModuleTypeInfo(string filename)
{
    import std.string : startsWith;
    import std.mmfile;
    import std.array : appender;

    // TODO: maybe a memory mapped file isn't the best?
    verbosef("reading module type from '%s'", filename);

    auto file = new MmFile(filename, MmFile.Mode.read, 0, null, 512);
    size_t offset = 0;
    auto data = cast(const(char)[])file[0 .. file.length];

    if (data.startsWith("#!"))
        offset = skipLine(data, offset + 2);
    if (offset >= data.length)
        return OptionalModuleTypeInfo.entry(null);

    // parse directives
    auto compilerArgs = appender!(string[])();
    {
        auto read = LineReader(data, offset);
        processDirectivesFromReader(compilerArgs, filename, &LineReader(data, offset).readln);
    }

    {
        auto error = skipWhitespaceAndComments(data, &offset);
        if (error)
            return OptionalModuleTypeInfo.error(error);
        if (offset >= data.length)
            return OptionalModuleTypeInfo.entry(compilerArgs.data);
    }

    if (!data[offset .. $].startsWith("module"))
        return OptionalModuleTypeInfo.entry(compilerArgs.data);
    offset += 6;
    if (offset >= data.length || !isWhitespace(data[offset]))
        return OptionalModuleTypeInfo.entry(compilerArgs.data);

    auto nameBuilder = appender!(char[])();
    for (;;)
    {
        {
            auto error = skipWhitespaceAndComments(data, &offset);
            if (error)
                return OptionalModuleTypeInfo.error(error);
            if (offset >= data.length)
                return OptionalModuleTypeInfo.error("module name did not end with ';'");
        }

        auto idStart = offset;
        offset = scanIdentifier(data, offset);
        if (idStart == offset)
            return OptionalModuleTypeInfo.error("module name contained invalid characters");

        nameBuilder.put(data[idStart .. offset]);

        {
            auto error = skipWhitespaceAndComments(data, &offset);
            if (error)
                return OptionalModuleTypeInfo.error(error);
            if (offset >= data.length)
                return OptionalModuleTypeInfo.error("module name did not end with ';'");
        }

        auto c = data[offset++];
        if (c == ';')
        {
            if (nameBuilder.data == "__none") // special case
                return OptionalModuleTypeInfo.entry(compilerArgs.data);
            return OptionalModuleTypeInfo.package_(compilerArgs.data, nameBuilder.data.assumeUnique);
        }
        if (c != '.')
            return OptionalModuleTypeInfo.error("module name contained invalid characters");
        nameBuilder.put('.');
    }
}

private bool isIdentifierStart(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
private bool isIdentifierChar(char c)
{
    return isIdentifierStart(c) || (c >= '0' && c <= '9');
}

private size_t scanIdentifier(const(char)[] str, size_t offset)
{
    if (offset < str.length && isIdentifierStart(str[offset]))
    {
        offset++;
        for (; offset < str.length; offset++)
        {
            if (!isIdentifierChar(str[offset]))
                break;
        }
    }
    return offset;
}

// returns error on error
private string skipWhitespaceAndComments(const(char)[] str, size_t* offsetPtr)
{
    auto offset = *offsetPtr;
    scope (exit) *offsetPtr = offset;

    for (; offset < str.length;)
    {
        auto c = str[offset];
        if (isWhitespace(c))
            offset++;
        else if (c == '/')
        {
            offset++;
            auto error = skipComment(str, &offset);
            if (error)
                return error;
        }
        else
            break;
    }
    return null; // success
}

//
// NOTE: this code should be kept in sync with github.com/dlang/dmd/blob/master/src/dmd/lexer.c
//
private bool isWhitespace(char c)
{
    return c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\v' || c == '\f';
}

private size_t skipLine(const(char)[] str, size_t offset)
{
    for (; offset < str.length; offset++)
    {
        if (str[offset] == '\n')
        {
            offset++;
            break;
        }
    }
    return offset;
}

private string skipComment(const(char)[] str, size_t* offsetPtr)
{
    auto offset = *offsetPtr;
    scope (exit) *offsetPtr = offset;

    if (offset >= str.length)
        return "invalid comment, '/' followed by EOF";
    auto first = str[offset];
    offset++;
    if (first == '/')
    {
        offset = skipLine(str, offset);
        return null;
    }
    if (first == '*')
    {
        enum UnterminatedCommentMessage = "unterminated /* */ comment";
        offset++;
        if (offset >= str.length)
            return UnterminatedCommentMessage;
        for(;;)
        {
            offset++;
            if (offset >= str.length)
                return UnterminatedCommentMessage;
            const c = str[offset];
            if (c == '/' && str[offset - 1] == '*')
            {
                offset++;
                return null; // pass
            }
        }
    }
    if (first == '+')
    {
        return "/+ multiline comments not impl +/";
    }
    return "invalid comment, '/' followed by unexpected character";
}

struct LineReader
{
    const(char)[] data;
    size_t offset;
    string readln()
    {
        auto start = offset;
        for (;;)
        {
            if (offset >= data.length)
            {
                offset = data.length;
                break;
            }
            auto c = data[offset];
            offset++;
            if (c == '\n')
                break;
        }
        return data[start .. offset].stripNewline().idup;
    }
}
