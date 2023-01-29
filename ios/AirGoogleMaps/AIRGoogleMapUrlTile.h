//
//  AIRGoogleMapURLTile.h
//  Created by Nick Italiano on 11/5/16.
//

#ifdef HAVE_GOOGLE_MAPS

#import <Foundation/Foundation.h>
#import <GoogleMaps/GoogleMaps.h>
#import "sqlite3.h"

@interface MyTileLayer : GMSTileLayer
    -(id)initWithDb:(sqlite3*)db;
@end

@interface AIRGoogleMapUrlTile : UIView

@property (nonatomic, strong) MyTileLayer *tileLayer;
@property (nonatomic, assign) NSString *urlTemplate;
@property (nonatomic, assign) int zIndex;
@property NSInteger *maximumZ;
@property NSInteger *minimumZ;
@property BOOL flipY;

@end

#endif
