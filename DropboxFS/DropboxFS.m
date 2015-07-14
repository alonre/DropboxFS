//
//  DropboxFS.m
//  DropboxFS
//
//  Created by Alon Regev on 7/13/15.
//  Copyright (c) 2015 Regunix. All rights reserved.
//

#import "DropboxFS.h"
#import <sys/xattr.h>
#import <sys/stat.h>
#import <sys/vnode.h>
#import <OSXFUSE/OSXFUSE.h>
#import "NSError+POSIX.h"


@implementation DropboxFS

- (id)initWithRootPath:(NSString *)rootPath {
    if ((self = [super init])) {
        rootPath_ = rootPath;
    }
    return self;
}

#pragma mark Moving an Item

- (BOOL)moveItemAtPath:(NSString *)source
                toPath:(NSString *)destination
                 error:(NSError **)error {
    // We use rename directly here since NSFileManager can sometimes fail to
    // rename and return non-posix error codes.
    NSString* p_src = [rootPath_ stringByAppendingString:source];
    NSString* p_dst = [rootPath_ stringByAppendingString:destination];
    int ret = rename([p_src UTF8String], [p_dst UTF8String]);
    if ( ret < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    return YES;
}

#pragma mark Removing an Item

- (BOOL)removeDirectoryAtPath:(NSString *)path error:(NSError **)error {
    // We need to special-case directories here and use the bsd API since
    // NSFileManager will happily do a recursive remove :-(
    NSString* p = [rootPath_ stringByAppendingString:path];
    int ret = rmdir([p UTF8String]);
    if (ret < 0) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    return YES;
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    // NOTE: If removeDirectoryAtPath is commented out, then this may be called
    // with a directory, in which case NSFileManager will recursively remove all
    // subdirectories. So be careful!
    NSString* p = [rootPath_ stringByAppendingString:path];
    return [[NSFileManager defaultManager] removeItemAtPath:p error:error];
}

#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)path
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    return [[NSFileManager defaultManager] createDirectoryAtPath:p
                                     withIntermediateDirectories:NO
                                                      attributes:attributes
                                                           error:error];
}

- (BOOL)createFileAtPath:(NSString *)path
              attributes:(NSDictionary *)attributes
                userData:(id *)userData
                   error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    mode_t mode = [[attributes objectForKey:NSFilePosixPermissions] longValue];
    int fd = creat([p UTF8String], mode);
    if ( fd < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    *userData = [NSNumber numberWithLong:fd];
    return YES;
}

#pragma mark Linking an Item

- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError **)error {
    NSString* p_path = [rootPath_ stringByAppendingString:path];
    NSString* p_otherPath = [rootPath_ stringByAppendingString:otherPath];
    
    // We use link rather than the NSFileManager equivalent because it will copy
    // the file rather than hard link if part of the root path is a symlink.
    int rc = link([p_path UTF8String], [p_otherPath UTF8String]);
    if ( rc <  0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    return YES;
}

#pragma mark Symbolic Links

- (BOOL)createSymbolicLinkAtPath:(NSString *)path
             withDestinationPath:(NSString *)otherPath
                           error:(NSError **)error {
    NSString* p_src = [rootPath_ stringByAppendingString:path];
    return [[NSFileManager defaultManager] createSymbolicLinkAtPath:p_src
                                                withDestinationPath:otherPath
                                                              error:error];
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    return [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:p
                                                                     error:error];
}

#pragma mark File Contents

- (BOOL)openFileAtPath:(NSString *)path
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    int fd = open([p UTF8String], mode);
    if ( fd < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    *userData = [NSNumber numberWithLong:fd];
    return YES;
}

- (void)releaseFileAtPath:(NSString *)path userData:(id)userData {
    NSNumber* num = (NSNumber *)userData;
    int fd = [num longValue];
    close(fd);
}

- (int)readFileAtPath:(NSString *)path
             userData:(id)userData
               buffer:(char *)buffer
                 size:(size_t)size
               offset:(off_t)offset
                error:(NSError **)error {
    NSNumber* num = (NSNumber *)userData;
    int fd = [num longValue];
    int ret = pread(fd, buffer, size, offset);
    if ( ret < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return -1;
    }
    return ret;
}

- (int)writeFileAtPath:(NSString *)path
              userData:(id)userData
                buffer:(const char *)buffer
                  size:(size_t)size
                offset:(off_t)offset
                 error:(NSError **)error {
    NSNumber* num = (NSNumber *)userData;
    int fd = [num longValue];
    int ret = pwrite(fd, buffer, size, offset);
    if ( ret < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return -1;
    }
    return ret;
}

- (BOOL)preallocateFileAtPath:(NSString *)path
                     userData:(id)userData
                      options:(int)options
                       offset:(off_t)offset
                       length:(off_t)length
                        error:(NSError **)error {
    NSNumber* num = (NSNumber *)userData;
    int fd = [num longValue];
    
    fstore_t fstore;
    
    fstore.fst_flags = 0;
    if ( options & ALLOCATECONTIG ) {
        fstore.fst_flags |= F_ALLOCATECONTIG;
    }
    if ( options & ALLOCATEALL ) {
        fstore.fst_flags |= F_ALLOCATEALL;
    }
    
    if ( options & ALLOCATEFROMPEOF ) {
        fstore.fst_posmode = F_PEOFPOSMODE;
    } else if ( options & ALLOCATEFROMVOL ) {
        fstore.fst_posmode = F_VOLPOSMODE;
    }
    
    fstore.fst_offset = offset;
    fstore.fst_length = length;
    
    if ( fcntl(fd, F_PREALLOCATE, &fstore) == -1 ) {
        *error = [NSError errorWithPOSIXCode:errno];
        return NO;
    }
    return YES;
}

- (BOOL)exchangeDataOfItemAtPath:(NSString *)path1
                  withItemAtPath:(NSString *)path2
                           error:(NSError **)error {
    NSString* p1 = [rootPath_ stringByAppendingString:path1];
    NSString* p2 = [rootPath_ stringByAppendingString:path2];
    int ret = exchangedata([p1 UTF8String], [p2 UTF8String], 0);
    if ( ret < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    return YES;
}

#pragma mark Directory Contents

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:p error:error];
}

#pragma mark Getting and Setting Attributes

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path
                                userData:(id)userData
                                   error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    NSDictionary* attribs =
    [[NSFileManager defaultManager] attributesOfItemAtPath:p error:error];
    return attribs;
}

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    NSDictionary* d =
    [[NSFileManager defaultManager] attributesOfFileSystemForPath:p error:error];
    if (d) {
        NSMutableDictionary* attribs = [NSMutableDictionary dictionaryWithDictionary:d];
        [attribs setObject:[NSNumber numberWithBool:YES]
                    forKey:kGMUserFileSystemVolumeSupportsExtendedDatesKey];
        
        NSURL *URL = [NSURL fileURLWithPath:p isDirectory:YES];
        NSNumber *supportsCaseSensitiveNames = nil;
        [URL getResourceValue:&supportsCaseSensitiveNames
                       forKey:NSURLVolumeSupportsCaseSensitiveNamesKey
                        error:NULL];
        if (supportsCaseSensitiveNames == nil) {
            supportsCaseSensitiveNames = [NSNumber numberWithBool:YES];
        }
        [attribs setObject:supportsCaseSensitiveNames
                    forKey:kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey];
        
        return attribs;
    }
    return nil;
}

- (BOOL)setAttributes:(NSDictionary *)attributes
         ofItemAtPath:(NSString *)path
             userData:(id)userData
                error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    
    // TODO: Handle other keys not handled by NSFileManager setAttributes call.
    
    NSNumber* offset = [attributes objectForKey:NSFileSize];
    if ( offset ) {
        int ret = truncate([p UTF8String], [offset longLongValue]);
        if ( ret < 0 ) {
            if ( error ) {
                *error = [NSError errorWithPOSIXCode:errno];
            }
            return NO;
        }
    }
    NSNumber* flags = [attributes objectForKey:kGMUserFileSystemFileFlagsKey];
    if (flags != nil) {
        int rc = chflags([p UTF8String], [flags intValue]);
        if (rc < 0) {
            if ( error ) {
                *error = [NSError errorWithPOSIXCode:errno];
            }
            return NO;
        }
    }
    return [[NSFileManager defaultManager] setAttributes:attributes
                                            ofItemAtPath:p
                                                   error:error];
}

#pragma mark Extended Attributes

- (NSArray *)extendedAttributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    
    ssize_t size = listxattr([p UTF8String], nil, 0, XATTR_NOFOLLOW);
    if ( size < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return nil;
    }
    NSMutableData* data = [NSMutableData dataWithLength:size];
    size = listxattr([p UTF8String], [data mutableBytes], [data length], XATTR_NOFOLLOW);
    if ( size < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return nil;
    }
    NSMutableArray* contents = [NSMutableArray array];
    char* ptr = (char *)[data bytes];
    while ( ptr < ((char *)[data bytes] + size) ) {
        NSString* s = [NSString stringWithUTF8String:ptr];
        [contents addObject:s];
        ptr += ([s length] + 1);
    }
    return contents;
}

- (NSData *)valueOfExtendedAttribute:(NSString *)name
                        ofItemAtPath:(NSString *)path
                            position:(off_t)position
                               error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    
    ssize_t size = getxattr([p UTF8String], [name UTF8String], nil, 0,
                            position, XATTR_NOFOLLOW);
    if ( size < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return nil;
    }
    NSMutableData* data = [NSMutableData dataWithLength:size];
    size = getxattr([p UTF8String], [name UTF8String],
                    [data mutableBytes], [data length],
                    position, XATTR_NOFOLLOW);
    if ( size < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return nil;
    }
    return data;
}

- (BOOL)setExtendedAttribute:(NSString *)name
                ofItemAtPath:(NSString *)path
                       value:(NSData *)value
                    position:(off_t)position
                     options:(int)options
                       error:(NSError **)error {
    // Setting com.apple.FinderInfo happens in the kernel, so security related
    // bits are set in the options. We need to explicitly remove them or the call
    // to setxattr will fail.
    // TODO: Why is this necessary?
    options &= ~(XATTR_NOSECURITY | XATTR_NODEFAULT);
    NSString* p = [rootPath_ stringByAppendingString:path];
    int ret = setxattr([p UTF8String], [name UTF8String],
                       [value bytes], [value length],
                       position, options | XATTR_NOFOLLOW);
    if ( ret < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    return YES;
}

- (BOOL)removeExtendedAttribute:(NSString *)name
                   ofItemAtPath:(NSString *)path
                          error:(NSError **)error {
    NSString* p = [rootPath_ stringByAppendingString:path];
    int ret = removexattr([p UTF8String], [name UTF8String], XATTR_NOFOLLOW);
    if ( ret < 0 ) {
        if ( error ) {
            *error = [NSError errorWithPOSIXCode:errno];
        }
        return NO;
    }
    return YES;
}


@end
