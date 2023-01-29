//
//  AIRGoogleMapURLTile.m
//  Created by Nick Italiano on 11/5/16.
//

#ifdef HAVE_GOOGLE_MAPS

#import "AIRGoogleMapUrlTile.h"
#import "sqlite3.h"
#import "MBTilesDbProvider.h"
#include <regex.h>
#include <math.h>

@implementation MyTileLayer {
    sqlite3* _db;
}

-(id)initWithDb:(sqlite3 *)db {
    self = [super init];
    _db = db;
    return self;
}

- (UIImage*) loadTileForX:(NSUInteger)x y:(NSUInteger)y zoom:(NSUInteger)z {
    NSString *sql = @"SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=? LIMIT 1";
    
    const char *sql_stmt = [sql UTF8String];
    NSError *error = nil;
    sqlite3_stmt *statement;
    int result, i, column_type, count;
    int previousRowsAffected, nowRowsAffected, diffRowsAffected;
    long long previousInsertId, nowInsertId;
    BOOL keepGoing = YES;
    BOOL hasInsertId;
    NSMutableDictionary *resultSet = [NSMutableDictionary dictionaryWithCapacity:0];
    NSMutableArray *resultRows = [NSMutableArray arrayWithCapacity:0];
    NSMutableDictionary *entry;
    NSData *imgBlobData;
    NSObject *columnValue;
    NSString *columnName;
    NSObject *insertId;
    NSObject *rowsAffected;
    
    UIImage* tile = nil;
    
    hasInsertId = NO;
    previousRowsAffected = sqlite3_total_changes(_db);
    previousInsertId = sqlite3_last_insert_rowid(_db);
    
    if (sqlite3_prepare_v2(_db, sql_stmt, -1, &statement, NULL) != SQLITE_OK) {
        //      error = [SQLite captureSQLiteErrorFromDb:db];
        error = [NSError new];
        keepGoing = NO;
    } else {
        
        int yTms = pow(2, (int)z) - 1 - (int)y;
        
        sqlite3_bind_int(statement, 1, (int)z);
        sqlite3_bind_int(statement, 2, (int)x);
        sqlite3_bind_int(statement, 3, yTms);
    }
    
    
    //    RCTLog(@"inside executeSqlWithDict");
    while (keepGoing) {
        result = sqlite3_step (statement);
        switch (result) {
                
            case SQLITE_ROW:
                i = 0;
                entry = [NSMutableDictionary dictionaryWithCapacity:0];
                count = sqlite3_column_count(statement);
                
                while (i < count) {
                    columnValue = nil;
                    columnName = [NSString stringWithFormat:@"%s", sqlite3_column_name(statement, i)];
                    
                    column_type = sqlite3_column_type(statement, i);
                    switch (column_type) {
                        case SQLITE_INTEGER:
                            columnValue = [NSNumber numberWithLongLong: sqlite3_column_int64(statement, i)];
                            break;
                        case SQLITE_FLOAT:
                            columnValue = [NSNumber numberWithDouble: sqlite3_column_double(statement, i)];
                            break;
                        case SQLITE_BLOB:
                            columnValue = imgBlobData = [NSData dataWithBytes:sqlite3_column_blob(statement, i) length:sqlite3_column_bytes(statement, i)];
                            tile = [UIImage imageWithData:imgBlobData];
                            break;
                        case SQLITE_TEXT:
                            columnValue = [[NSString alloc] initWithBytes:(char *)sqlite3_column_text(statement, i)
                                                                   length:sqlite3_column_bytes(statement, i)
                                                                 encoding:NSUTF8StringEncoding];
#if !__has_feature(objc_arc)
                            [columnValue autorelease];
#endif
                            break;
                        case SQLITE_NULL:
                            // just in case (should not happen):
                        default:
                            columnValue = [NSNull null];
                            break;
                    }
                    
                    if (columnValue) {
                        [entry setObject:columnValue forKey:columnName];
                    }
                    
                    i++;
                }
                [resultRows addObject:entry];
                break;
                
            case SQLITE_DONE:
                nowRowsAffected = sqlite3_total_changes(_db);
                diffRowsAffected = nowRowsAffected - previousRowsAffected;
                rowsAffected = [NSNumber numberWithInt:diffRowsAffected];
                nowInsertId = sqlite3_last_insert_rowid(_db);
                if (nowRowsAffected > 0 && nowInsertId != 0) {
                    hasInsertId = YES;
                    insertId = [NSNumber numberWithLongLong:sqlite3_last_insert_rowid(_db)];
                }
                keepGoing = NO;
                break;
                
            default:
                error = [NSError new];// [SQLite captureSQLiteErrorFromDb:db];
                keepGoing = NO;
        }
    }
    
    sqlite3_finalize (statement);
    
    if (error) {
        return nil;
    } else {
        return tile;
    }
}


-(float) tile2long:(NSUInteger)x zoom:(NSUInteger)zoom {
    return (x / pow(2, zoom) * 360.0 - 180.0);
}
-(float) tile2lat:(NSUInteger)y zoom:(NSUInteger)z {
    float n = M_PI - 2 * M_PI * y / pow(2, z);
    return (180.0 / M_PI * atan(0.5 * (exp(n) - exp(-n))));
}

-(float) lon2tile:(float)lon zoom:(NSUInteger)zoom {
    return (lon + 180.0) / 360.0 * pow(2, zoom);
}

- (float) lat2tile:(float)lat zoom:(NSUInteger)zoom {
    return (1.0 - log(tan(lat * M_PI / 180.0) + 1.0 / cos(lat * M_PI / 180.0)) / M_PI) / 2 * pow(2.0, zoom);
}

- (UIImage *)cropImage:(UIImage *)imageToCrop toRect:(CGRect)rect
{
    CGImageRef imageRef = CGImageCreateWithImageInRect([imageToCrop CGImage], rect);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    return cropped;
}

- (UIImage *)imageWithImage:(UIImage *)image scaledToSize:(CGSize)newSize {
    //UIGraphicsBeginImageContext(newSize);
    // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
    // Pass 1.0 to force exact pixel size.
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (void)requestTileForX:(NSUInteger)x y:(NSUInteger)y zoom:(NSUInteger)z receiver:(id<GMSTileReceiver>)receiver {
    
    if (_db == nil) {
        [receiver receiveTileWithX:x y:y zoom:z image:nil];
        return;
    }
    
    UIImage* tile = [self loadTileForX:x y:y zoom:z];
    if (tile == nil) {
        float parentX = [self lon2tile: [self tile2long:x zoom: z] zoom:z-1];
        float parentY = [self lat2tile: [self tile2lat:y zoom: z] zoom:z-1];
        
        int parentXInt = floor(parentX);
        int parentYInt = floor(parentY);
        
        tile = [self loadTileForX:parentXInt y:parentYInt zoom:z-1];
        if (tile != nil) {
            //TODO determine quadrant, resize and zoom on the quadrant
            int imageSize = 256;
            int cropX = 0;
            int cropY = 0;
            if (fabs(parentX - parentXInt)  > 0.5) {
                cropX = imageSize / 2;
            }
            if (fabs(parentY - parentYInt)  > 0.5) {
                cropY = imageSize / 2;
            }
            CGRect cropRect = CGRectMake(cropX, cropY, imageSize / 2, imageSize / 2);
            UIImage* croppedImage = [self cropImage:tile toRect:cropRect];
            tile = [self imageWithImage:croppedImage scaledToSize:CGSizeMake(imageSize, imageSize)];
        }
    }
    
    [receiver receiveTileWithX:x y:y zoom:z image:tile];
}

@end

@implementation AIRGoogleMapUrlTile {
    sqlite3 *_db;
}

static void sqlite_regexp(sqlite3_context* context, int argc, sqlite3_value** values) {
    if ( argc < 2 ) {
        sqlite3_result_error(context, "SQL function regexp() called with missing arguments.", -1);
        return;
    }
    
    char* reg  = (char*) sqlite3_value_text(values[0]);
    char* text = (char*) sqlite3_value_text(values[1]);
    
    if ( argc != 2 || reg == 0 || text == 0) {
        sqlite3_result_error(context, "SQL function regexp() called with invalid arguments.", -1);
        return;
    }
    
    int ret;
    regex_t regex;
    
    ret = regcomp(&regex, reg, REG_EXTENDED | REG_NOSUB);
    if ( ret != 0 ) {
        sqlite3_result_error(context, "error compiling regular expression", -1);
        return;
    }
    
    ret = regexec(&regex, text , 0, NULL, 0);
    regfree(&regex);
    
    sqlite3_result_int(context, (ret != REG_NOMATCH));
}

- (void)setZIndex:(int)zIndex
{
    _zIndex = zIndex;
    _tileLayer.zIndex = zIndex;
}

- (void)resetMbTileDatabase
{
    if (_db != nil) {
        sqlite3_close(_db);
        _db = nil;
    }
    if (_urlTemplate != nil) {
        _db = [[MBTilesDbProvider singleton] getDb:_urlTemplate];
    }
    _tileLayer = [[MyTileLayer alloc] initWithDb:_db];
    _tileLayer.tileSize = [[UIScreen mainScreen] scale] * 256;
}

- (void)setMbTileDbEtag:(NSString *)mbTileDbEtag
{
    if (_mbTileDbEtag == mbTileDbEtag || [_mbTileDbEtag isEqualToString:mbTileDbEtag]) {
        return;
    }
    [self resetMbTileDatabase];
    _mbTileDbEtag = mbTileDbEtag;
}

- (void)setUrlTemplate:(NSString *)urlTemplate
{
    _urlTemplate = urlTemplate;
    if (urlTemplate != nil) {
        _db = [[MBTilesDbProvider singleton] getDb:urlTemplate];
    }
    _tileLayer = [[MyTileLayer alloc] initWithDb:_db];
    _tileLayer.tileSize = [[UIScreen mainScreen] scale] * 256;
}

@end

#endif
