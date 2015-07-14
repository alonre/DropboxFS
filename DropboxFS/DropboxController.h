//
//  DropboxController.h
//  DropboxFS
//
//  Created by Alon Regev on 7/13/15.
//  Copyright (c) 2015 Regunix. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class GMUserFileSystem;
@class DropboxFS;


@interface DropboxController : NSObject {

GMUserFileSystem* fs_;
DropboxFS* drop_;
    
}

@end
