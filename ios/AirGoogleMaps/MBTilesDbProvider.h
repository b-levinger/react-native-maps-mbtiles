#import <Foundation/Foundation.h>
#import "sqlite3.h"

@interface MBTilesDbProvider : NSObject
    + singleton;
    -(sqlite3*) getDb:(NSString*)forPath;
@end
