#import "LaunchDaemon.h"

NSDictionary *normalizeLaunchDaemon(NSDictionary *source, NSString *rootPath)
{
    if (![source isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSString *label = source[@"Label"];
    if (![label isKindOfClass:NSString.class] || label.length == 0 || [label containsString:@"/"]) {
        return nil;
    }

    NSString *program = source[@"Program"];
    if (program && (![program isKindOfClass:NSString.class] || program.length == 0)) {
        return nil;
    }

    NSArray *arguments = source[@"ProgramArguments"];
    if (arguments && (![arguments isKindOfClass:NSArray.class] || arguments.count == 0)) {
        return nil;
    }
    for (id argument in arguments) {
        if (![argument isKindOfClass:NSString.class]) {
            return nil;
        }
    }

    NSString *executablePath = program;
    if (!executablePath) {
        executablePath = arguments.firstObject;
    }
    if (![executablePath hasPrefix:@"/"] || [executablePath.pathComponents containsObject:@".."]) {
        return nil;
    }

    NSString *rootPrefix = [rootPath stringByAppendingString:@"/"];
    NSString *qualifiedPath = executablePath;
    if (![executablePath hasPrefix:rootPrefix]) {
        qualifiedPath = [rootPath stringByAppendingString:executablePath];
    }

    NSMutableDictionary *job = [source mutableCopy];
    job[@"Program"] = qualifiedPath;
    if (arguments) {
        NSMutableArray *updatedArguments = [arguments mutableCopy];
        if ([arguments.firstObject isEqualToString:executablePath]) {
            updatedArguments[0] = qualifiedPath;
        }
        job[@"ProgramArguments"] = updatedArguments;
    }

    NSDictionary *existingEnvironment = source[@"EnvironmentVariables"];
    if (existingEnvironment && ![existingEnvironment isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSMutableDictionary *environment = [existingEnvironment mutableCopy];
    if (!environment) {
        environment = [NSMutableDictionary dictionary];
    }
    environment[@"CRYPTEX_MOUNT_PATH"] = rootPath;
    job[@"EnvironmentVariables"] = environment;
    return job;
}
