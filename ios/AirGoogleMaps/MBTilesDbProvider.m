//
//  MBTilesDbProvider.m
//  AirMaps
//
//  Created by Brandon Levinger on 5/20/22.
//  Copyright © 2022 Christopher. All rights reserved.
//
#import "MBTilesDbProvider.h"
#import "sqlite3.h"
#include <regex.h>

@implementation MBTilesDbProvider {
    NSMutableDictionary* _dbs;// = [NSMutableDictionary dictionaryWithCapacity:0];
}

static MBTilesDbProvider *singletonObject = nil;

+ (id) singleton
{
    if (! singletonObject) {
        
        singletonObject = [[MBTilesDbProvider alloc] init];
    }
    return singletonObject;
}

- (id)init
{
    if (! singletonObject) {
        singletonObject = [super init];
        [singletonObject initialze];
    }
    return singletonObject;
}

-(void)initialze {
    _dbs = [NSMutableDictionary dictionaryWithCapacity:0];
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

-(sqlite3*)getDb:(NSString*)forPath {
    @synchronized (self) {
        NSDictionary *dbInfo = _dbs[forPath];
        if (dbInfo == NULL || dbInfo[@"dbPointer"] == NULL) {
            sqlite3* db = [self openDb:forPath];
            NSValue *dbPointer = [NSValue valueWithPointer: db];
            dbInfo = _dbs[forPath] = @{ @"dbPointer": dbPointer, @"dbPath" : forPath };
        }
        sqlite3 *db = [((NSValue *) dbInfo[@"dbPointer"]) pointerValue];
        return db;
    }
}

-(sqlite3*) openDb:(NSString*)pathTemplate
{
    //    SQLiteResult* pluginResult = nil;
    NSString *dbname = pathTemplate;
    int sqlOpenFlags = SQLITE_OPEN_READONLY;
    sqlite3 *db;
    
    
    //RCTLog(@"Opening db in mode %@, full path: %@", (sqlOpenFlags == SQLITE_OPEN_READONLY) ? @"READ ONLY" : @"READ_WRITE",dbname);
    const char *name = [dbname UTF8String];
    if (sqlite3_open_v2(name, &db,sqlOpenFlags, NULL) != SQLITE_OK) {
        //            pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:@"Unable to open DB"];
        return nil;
    } else {
        sqlite3_create_function(db, "regexp", 2, SQLITE_ANY, NULL, &sqlite_regexp, NULL, NULL);
        const char *key = NULL;
        
#ifdef SQLCIPHER
        NSString *dbkey = options[@"key"];
        if (dbkey != NULL) {
            key = [dbkey UTF8String];
            if (key != NULL) {
                sqlite3_key(db, key, strlen(key));
            }
        }
#endif
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
        // Attempt to read the SQLite master table [to support SQLCipher version]:
        if(sqlite3_exec(db, (const char*)"SELECT count(*) FROM sqlite_master;", NULL, NULL, NULL) == SQLITE_OK) {
            //_db = db;
            NSString *msg = (key != NULL) ? @"Secure database opened" : @"Database opened";
            //                pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_OK messageAsString: msg];
            //RCTLog(@"%@", msg);
        } else {
            NSString *msg = [NSString stringWithFormat:@"Unable to open %@", (key != NULL) ? @"secure database with key" : @"database"];
            //                pluginResult = [SQLiteResult resultWithStatus:SQLiteStatus_ERROR messageAsString:msg];
            //RCTLog(@"%@", msg);
            sqlite3_close (db);
            //[openDBs removeObjectForKey:dbfilename];
        }
    }
    return db;
}


@end
