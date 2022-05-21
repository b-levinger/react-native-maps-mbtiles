//
//  AIRGoogleMapURLTile.m
//  Created by Nick Italiano on 11/5/16.
//

#ifdef HAVE_GOOGLE_MAPS

#import "AIRGoogleMapUrlTile.h"
#import "sqlite3.h"
#include <regex.h>
#imprt "MBTilesDbProvider.h"

@implementation MyTileLayer {
    sqlite3* _db;
}

-(id)initWithDb:(sqlite3 *)db {
    self = [super init];
    _db = db;
    return self;
}

- (void)requestTileForX:(NSUInteger)x y:(NSUInteger)y zoom:(NSUInteger)z receiver:(id<GMSTileReceiver>)receiver {

    if (_db == nil) {
        [receiver receiveTileWithX:x y:y zoom:z image:nil];
        return;
    }

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
//            resultCb(nil, error);
        } else {
            [resultSet setObject:resultRows forKey:@"rows"];
            [resultSet setObject:rowsAffected forKey:@"rowsAffected"];
            if (hasInsertId) {
                [resultSet setObject:insertId forKey:@"insertId"];
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


//-(void) openDb:(NSString*)pathTemplate
//{
//    //    SQLiteResult* pluginResult = nil;
//    NSString *dbname = pathTemplate;
//    int sqlOpenFlags = SQLITE_OPEN_READONLY;
//
//    @synchronized (self) {
//        //RCTLog(@"Opening db in mode %@, full path: %@", (sqlOpenFlags == SQLITE_OPEN_READONLY) ? @"READ ONLY" : @"READ_WRITE",dbname);
//        const char *name = [dbname UTF8String];
//        sqlite3 *db;
//        if (sqlite3_open_v2(name, &db,sqlOpenFlags, NULL) != SQLITE_OK) {
//            //            pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"Unable to open DB"];
//            return;
//        } else {
//            sqlite3_create_function(db, "regexp", 2, SQLITE_ANY, NULL, &sqlite_regexp, NULL, NULL);
//            const char *key = NULL;
//
//#ifdef SQLCIPHER
//            NSString *dbkey = options[@"key"];
//            if (dbkey != NULL) {
//                key = [dbkey UTF8String];
//                if (key != NULL) {
//                    sqlite3_key(db, key, strlen(key));
//                }
//            }
//#endif
//            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
//            // Attempt to read the SQLite master table [to support SQLCipher version]:
//            if(sqlite3_exec(db, (const char*)"SELECT count(*) FROM sqlite_master;", NULL, NULL, NULL) == SQLITE_OK) {
//                _db = db;
//                NSString *msg = (key != NULL) ? @"Secure database opened" : @"Database opened";
//                //                pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString: msg];
//                //RCTLog(@"%@", msg);
//            } else {
//                NSString *msg = [NSString stringWithFormat:@"Unable to open %@", (key != NULL) ? @"secure database with key" : @"database"];
//                //                pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:msg];
//                //RCTLog(@"%@", msg);
//                sqlite3_close (db);
//                //[openDBs removeObjectForKey:dbfilename];
//            }
//        }
//    }
//
//    if (sqlite3_threadsafe()) {
////        RCTLog(@"Good news: SQLite is thread safe!");
//    } else {
////        RCTLog(@"Warning: SQLite is not thread safe.");
//    }
// //   RCTLog(@"open cb finished ok");
//}

- (void)setZIndex:(int)zIndex
{
    _zIndex = zIndex;
    _tileLayer.zIndex = zIndex;
}

- (void)setUrlTemplate:(NSString *)urlTemplate
{
    _urlTemplate = urlTemplate;
    if (urlTemplate) {
        _db = [[MBTilesDbPRovider singleton] getDb:urlTemplate];
    }
    _tileLayer = [[MyTileLayer alloc] initWithDb:_db];
    _tileLayer.tileSize = [[UIScreen mainScreen] scale] * 256;
}

@end

#endif
