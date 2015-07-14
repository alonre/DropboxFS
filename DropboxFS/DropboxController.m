//
//  DropboxController.m
//  DropboxFS
//
//  Created by Alon Regev on 7/13/15.
//  Copyright (c) 2015 Regunix. All rights reserved.
//

#import "DropboxController.h"
#import "DropboxFS.h"
#import <OSXFUSE/OSXFUSE.h>

#import <AvailabilityMacros.h>

@implementation DropboxController

- (void)mountFailed:(NSNotification *)notification {
    NSLog(@"Got mountFailed notification.");
    
    NSDictionary* userInfo = [notification userInfo];
    NSError* error = [userInfo objectForKey:kGMUserFileSystemErrorKey];
    NSLog(@"kGMUserFileSystem Error: %@, userInfo=%@", error, [error userInfo]);
    
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Mount Failed"];
    [alert setInformativeText:[error localizedDescription] ?: @"Unknown error"];
    [alert runModal];
    
    [[NSApplication sharedApplication] terminate:nil];
}

- (void)didMount:(NSNotification *)notification {
    NSLog(@"Got didMount notification.");
    
    NSDictionary* userInfo = [notification userInfo];
    NSString* mountPath = [userInfo objectForKey:kGMUserFileSystemMountPathKey];
    NSString* parentPath = [mountPath stringByDeletingLastPathComponent];
    [[NSWorkspace sharedWorkspace] selectFile:mountPath
                     inFileViewerRootedAtPath:parentPath];
}

- (void)didUnmount:(NSNotification*)notification {
    NSLog(@"Got didUnmount notification.");
    
    [[NSApplication sharedApplication] terminate:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    int ret = 0;
#if MAC_OS_X_VERSION_MIN_REQUIRED < 1060
    ret = [panel runModalForDirectory:@"/tmp" file:nil types:nil];
#else
    [panel setDirectoryURL:[NSURL fileURLWithPath:@"/tmp"]];
    ret = [panel runModal];
#endif
#if MAC_OS_X_VERSION_MIN_REQUIRED < 1090
    if ( ret == NSCancelButton )
#else
        if ( ret == NSModalResponseCancel )
#endif
        {
            exit(0);
        }
#if MAC_OS_X_VERSION_MIN_REQUIRED < 1060
    NSArray* paths = [panel filenames];
#else
    NSArray* paths = [panel URLs];
#endif
    if ( [paths count] != 1 ) {
        exit(0);
    }
    NSString* rootPath = nil;
#if MAC_OS_X_VERSION_MIN_REQUIRED < 1060
    rootPath = [paths objectAtIndex:0];
#else
    rootPath = [[paths objectAtIndex:0] path];
#endif
    
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(mountFailed:)
                   name:kGMUserFileSystemMountFailed object:nil];
    [center addObserver:self selector:@selector(didMount:)
                   name:kGMUserFileSystemDidMount object:nil];
    [center addObserver:self selector:@selector(didUnmount:)
                   name:kGMUserFileSystemDidUnmount object:nil];
    
    NSString* mountPath = @"/Volumes/Dropbox";
    drop_ = [[DropboxFS alloc] initWithRootPath:rootPath];
    
    fs_ = [[GMUserFileSystem alloc] initWithDelegate:drop_ isThreadSafe:NO];
    
    NSMutableArray* options = [NSMutableArray array];
    
    NSString* volArg =
    [NSString stringWithFormat:@"volicon=%@",
     [[NSBundle mainBundle] pathForResource:@"DropboxFS" ofType:@"icns"]];
    [options addObject:volArg];
    
    // Do not use the 'native_xattr' mount-time option unless the underlying
    // file system supports native extended attributes. Typically, the user
    // would be mounting an HFS+ directory through LoopbackFS, so we do want
    // this option in that case.
    [options addObject:@"native_xattr"];
    
    [options addObject:@"volname=DropboxFS"];
    [fs_ mountAtPath:mountPath
         withOptions:options];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [fs_ unmount];
    //[fs_ release];
    //[drop_ release];
    return NSTerminateNow;
}


@end
