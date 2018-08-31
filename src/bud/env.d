/**
This module is used to track save/restore the build environment.

Bud will hash everything in the compiler environment, i.e.

* the compiler (could be just the filename, could also include timestamp, could even hash the compiler binary)
* all environment variables passed to the compiler

NOTE: when bud invokes the compiler, it will remove all environment variables
except the ones that the compiler uses.

* all compiler command line variables
* any files that bud knows the compiler will use (i.e. the compiler configuration file)

*/
module bud.env;

struct BuildEnv
{
    
}
