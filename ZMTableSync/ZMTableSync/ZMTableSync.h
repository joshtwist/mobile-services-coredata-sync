//
//  ZMTableSync.h
//  Doto
//
//  Created by Josh Twist on 12/7/12.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <WindowsAzureMobileServices/WindowsAzureMobileServices.h>

// Used in the callback of synchronizeLocalChangesWithCallback method,
// indicates what type of operation took place
enum ZMSyncOperationType {
    ZMSyncOperationTypeCreate,
    ZMSyncOperationTypeUpdate,
    ZMSyncOperationTypeDelete,
};

// Used to represent the sync state in the local database, 'synced' means
// the local store believes this has been pushed to or retrieved from the cloud storage.
// 'Created' indicates that the item was created locally but didn't make it to the cloud store
// yet and will be pushed with the next call to synchronizeLocalChangesWithCallback
enum ZMSyncState{
    ZMSyncStateCreated = 1,
    ZMSyncStateUpdated = 2,
    ZMSyncStateDeleted = 3,
    ZMSyncStateSynced  = 0,
};

typedef void (^ZMSyncedResultBlock) (NSManagedObject* entity, NSError *error);
typedef void (^ZMSyncedResultsBlock) (NSArray* results, NSError *error);
typedef void (^ZMSyncOperationCallbackBlock) (enum ZMSyncOperationType operation, NSManagedObject *entity, NSDictionary *remote, NSError *error);


@interface ZMTableSync : NSObject

+ (ZMTableSync *)tableSyncWithTable: (MSTable *) table
                           entity: (NSString *) entityName
                           context: (NSManagedObjectContext *) context;

// Takes a dictionary and copies all the keys and values onto the entity
+ (void)mergeDictionary:(NSDictionary*) dictionary onEntity:(NSManagedObject *) entity;

// Takes an entity and copies all the keys and values onto the dictionary
+ (void)mergeEntity:(NSManagedObject *) entity onDictionary:(NSMutableDictionary *) dictionary;

- (id)createEntity;

- (void)insert:(NSManagedObject *) entity
     completion:(ZMSyncedResultBlock) completion;

- (void)update:(NSManagedObject *) entity
     completion:(ZMSyncedResultBlock) completion;

- (void)delete:(NSManagedObject *) entity
     completion:(ZMSyncedResultBlock) completion;

- (NSArray *)readWithPredicate:(NSPredicate *)predicate
               sortDescriptors:(NSArray *) sortDescriptors
                    completion:(ZMSyncedResultsBlock) completion;

- (void)synchronizeLocalChangesWithCallback:(ZMSyncOperationCallbackBlock) callback error: (NSError **) error;

@end
