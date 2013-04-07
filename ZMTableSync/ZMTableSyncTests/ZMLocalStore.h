//
//  LocalStore.h
//  Doto
//
//  Created by Josh Twist on 12/6/12.
//

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

@interface ZMLocalStore : NSObject

@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@end
