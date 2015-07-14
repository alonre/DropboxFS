//
//  DropboxFS.h
//  DropboxFS
//
//  Created by Alon Regev on 7/13/15.
//  Copyright (c) 2015 Regunix. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DropboxFS : NSObject {
    NSString* rootPath_;   // The local file-system path to mount.
}
- (id)initWithRootPath:(NSString *)rootPath;
@end
