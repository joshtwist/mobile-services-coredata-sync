//
//  ZMTableSync.m
//  Doto
//
//  Created by Josh Twist on 12/7/12.
//

#import "ZMTableSync.h"

#define ZMIDKey @"id"
#define ZMSyncStatusKey @"syncStatus"
#define ZMSyncTagKey @"syncTag"

@interface ZMTableSync ()

@property (strong, nonatomic)   MSTable *table;
@property (strong, nonatomic)   NSManagedObjectContext *context;
@property (strong, nonatomic)   NSString *entityName;
@property (nonatomic)           BOOL isDirty;

@end

@implementation ZMTableSync

+ (ZMTableSync *) tableSyncWithTable:(MSTable *)table entity:(NSString *)entityName context:(NSManagedObjectContext *) context
{
    ZMTableSync *syncTable = [[ZMTableSync alloc] init];
    syncTable.table = table;
    syncTable.context = context;
    syncTable.entityName = entityName;
    return syncTable;
}

+ (void) mergeDictionary:(NSDictionary*) dictionary onEntity:(NSManagedObject *) entity
{
    for (NSString *property in [dictionary allKeys])
    {
        id value = [dictionary valueForKey:property];
        if ([value isKindOfClass:[NSNull class]]){
            value = nil;
        }
        [entity setValue:value forKey:property];
    }
}

+ (void) mergeEntity:(NSManagedObject *) entity onDictionary:(NSMutableDictionary *) dictionary
{
    NSDictionary *metadata = [[entity entity] attributesByName];
    
    for (NSString *property in [metadata allKeys])
    {
        if ([property isEqualToString:ZMSyncStatusKey]){
            continue;
        }
        else if ([property isEqualToString:ZMIDKey]){
            id value = [entity valueForKey:property];
            if (![value isEqual: @0]){
                [dictionary setValue:[entity valueForKey:property] forKey:property];
            }
        }
        else{
            id value = [entity valueForKey:property];
            if (value == nil)
            {
                value = [NSNull null];
            }
            [dictionary setValue:value forKey:property];
        }
    }
}

- (NSManagedObject *)createEntity
{
    return [NSEntityDescription insertNewObjectForEntityForName:self.entityName inManagedObjectContext:self.context];
}

- (void)insert:(NSManagedObject *)entity completion:(ZMSyncedResultBlock)completion
{
    [entity setValue:@(ZMSyncStateCreated) forKey:ZMSyncStatusKey];
    NSMutableDictionary *zumoData = [[NSMutableDictionary alloc] init];
    [ZMTableSync mergeEntity:entity onDictionary:zumoData];
    // This is an insert so we can't have an id property, remove it
    [zumoData removeObjectForKey:ZMIDKey];
    [self.table insert:zumoData completion:^(NSDictionary *item, NSError *error) {
        if (!error) {
            [entity setValue:@(ZMSyncStateSynced) forKey:ZMSyncStatusKey];
            [ZMTableSync mergeDictionary:item onEntity:entity];
        }
        if (completion) {
            completion(entity, error);
        }
        [self dispatchSaveAsync];
    }];
    self.isDirty = YES;
}

- (void)update:(NSManagedObject *)entity completion:(ZMSyncedResultBlock)completion
{
    NSNumber *state = [entity valueForKey:ZMSyncStatusKey];
    // if the sync state is created, leave as created - not updated
    if (![state isEqual: @(ZMSyncStateCreated)]) {
        [entity setValue:@(ZMSyncStateUpdated) forKey:ZMSyncStatusKey];
    }
    NSMutableDictionary *zumoData = [[NSMutableDictionary alloc] init];
    [ZMTableSync mergeEntity:entity onDictionary:zumoData];
    [self.table update:zumoData completion:^(NSDictionary *item, NSError *error) {
        if (!error) {
            // TODO - check for 404, may just have been deleted
            [entity setValue:@(ZMSyncStateSynced) forKey:ZMSyncStatusKey];
            [ZMTableSync mergeDictionary:item onEntity:entity];
        }
        if (completion) {
            completion(entity, error);
        }
        [self dispatchSaveAsync];
    }];
    self.isDirty = YES;
}

- (void)delete:(NSManagedObject *)entity completion:(ZMSyncedResultBlock)completion
{
    NSNumber *state = [entity valueForKey:ZMSyncStatusKey];
    
    // if the item has been created locally only, we can just delete
    if ([state isEqual: @(ZMSyncStateCreated)]) {
        [self.context deleteObject:entity];
        completion(entity, nil);
        return;
    }
    [entity setValue:@(ZMSyncStateDeleted) forKey:ZMSyncStatusKey];
    [self.table deleteWithId:[entity valueForKey:ZMIDKey] completion:^(NSNumber *itemId, NSError *error) {
        if (!error) {
            // TODO - check for 404, may just have been deleted
            [self.context deleteObject:entity];
        }
        if (completion) {
            completion (entity, error);
        }
        [self dispatchSaveAsync];
    }];
    self.isDirty = YES;
}

- (NSArray *)readWithPredicate:(NSPredicate *)predicate sortDescriptors:(NSArray *) sortDescriptors completion:(ZMSyncedResultsBlock) completion
{
    NSFetchRequest *fr = [self fetchRequestEntity:self.entityName WithPredicate:predicate andSortDescriptors:sortDescriptors];
    
    NSError *error;
    
    NSArray *localResults = [self.context executeFetchRequest:fr error:&error];
    MSQuery *query = [self.table queryWhere:predicate];
    
    for (NSSortDescriptor *sd in sortDescriptors) {
        if (sd.ascending) {
            [query orderByAscending:sd.key];
        }   else
        {
            [query orderByDescending:sd.key];
        }
    }
    
    NSPredicate *notDeletedPredicate = [NSPredicate predicateWithFormat:@"syncStatus != %@", @(ZMSyncStateDeleted)];
    
    [query readWithCompletion:^(NSArray *results, NSInteger totalCount, NSError *error) {
        
        // if an error, don't peform the merge.
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSMutableArray *remoteResults = [results mutableCopy];
        NSMutableArray *deletions = [[NSMutableArray alloc] init];
        NSMutableArray *creations = [[NSMutableArray alloc] init];

        // Call the big sync. This should update the local database to hold the correct picture.
        // We can now requery the local database. Clearly, this is not optimum for performance.
        [ZMTableSync mergeLocalRecords:localResults intoRemoteRecords:remoteResults producingLocalDeletions:deletions andRemoteCreations:creations];
        
        // the merge dictated we should delete these records
        for (NSManagedObject* deletee in deletions) {
            [self.context deleteObject:deletee];
        }
        
        // and create these new ones
        for (NSDictionary *newRecord in creations) {
            NSManagedObject *newInstance = [self createEntity];
            [ZMTableSync mergeDictionary:newRecord onEntity:newInstance];
        }
        
        NSPredicate *predicate = fr.predicate == nil ? notDeletedPredicate : [NSCompoundPredicate andPredicateWithSubpredicates:@[fr.predicate, notDeletedPredicate]];
        
        NSFetchRequest *localMergeRequest = [self fetchRequestEntity:self.entityName WithPredicate:predicate andSortDescriptors:sortDescriptors];
        
        NSArray *allResults = [self.context executeFetchRequest:localMergeRequest error:&error];
        
        if (completion) {
            completion(allResults, error);
        }
    }];
    
    [self dispatchSaveAsync];
    
    id returnResults = [localResults filteredArrayUsingPredicate:notDeletedPredicate];
    
    return returnResults;
}

- (NSFetchRequest *) fetchRequestEntity: (NSString *) entityName
                          WithPredicate:(NSPredicate *) predicate
                     andSortDescriptors:(NSArray *) sortDescriptors
{
    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:entityName];
    fr.sortDescriptors = sortDescriptors;
    fr.predicate = predicate;
    return fr;
}

- (void)synchronizeLocalChangesWithCallback:(ZMSyncOperationCallbackBlock) callback error: (NSError **)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO - need to check syncTag, this should be done on the server.
        NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:self.entityName];
        fr.predicate = [NSPredicate predicateWithFormat:@"syncStatus != %@", @(ZMSyncStateSynced)];
        NSError *err = nil;
        NSArray *unsynced = [self.context executeFetchRequest:fr error:&err];
        // TODO - need to pass the synchronous error back to the caller - beware that we pass in nil externally
        // TODO - record or handle the error
        NSLog(@"Syncing '%@' - %d records...", self.table.name, unsynced.count);
        for (NSManagedObject *entity in unsynced) {
            NSNumber *state = [entity valueForKey:ZMSyncStatusKey];
            // DELETE
            if ([state isEqualToNumber:@(ZMSyncStateDeleted)]) {
                [self.table deleteWithId:[entity valueForKey:ZMIDKey] completion:^(NSNumber *itemId, NSError *error) {
                    if (!error) {
                        [self.context deleteObject:entity];
                    }
                    if (callback) {
                        callback(ZMSyncOperationTypeDelete, entity, nil, error);
                    }
                }];
            }
            // UPDATE 
            else if ([state isEqualToNumber:@(ZMSyncStateUpdated)]){
                NSMutableDictionary *newRemote = [[NSMutableDictionary alloc] init];
                [ZMTableSync mergeEntity:entity onDictionary:newRemote];
                [self.table update:newRemote completion:^(NSDictionary *item, NSError *error) {
                    if (!error) {
                        [entity setValue:@(ZMSyncStateSynced) forKey:ZMSyncStatusKey];
                        [ZMTableSync mergeDictionary:item onEntity:entity];
                    }
                    if (callback) {
                        callback(ZMSyncOperationTypeUpdate, entity, item, error);
                    }
                }];
            }
            // CREATE
            else if ([state isEqualToNumber:@(ZMSyncStateCreated)]){
                NSMutableDictionary *newRemote = [[NSMutableDictionary alloc] init];
                [ZMTableSync mergeEntity:entity onDictionary:newRemote];
                [self.table insert:newRemote completion:^(NSDictionary *item, NSError *error) {
                    if (!error) {
                        [entity setValue:@(ZMSyncStateSynced) forKey:ZMSyncStatusKey];
                        [ZMTableSync mergeDictionary:item onEntity:entity];
                    }
                    if (callback) {
                        callback(ZMSyncOperationTypeCreate, entity, item, error);
                    }
                }];
            }
        }
    });
    
}

+ (void) mergeLocalRecords:(NSArray *) localResults intoRemoteRecords:(NSMutableArray *) remote producingLocalDeletions:(NSMutableArray *) deletions andRemoteCreations:(NSMutableArray *) creations;
{
    // Now we begin the merge. We may have
    // 1. existing and changed items showing up
    // 2. new items from the remote that we don't have in our local
    // 3. missing items, that are in our local but not in the remote
    // 4. items that are in the remote but deleted in the local
    NSMutableArray *matched = [[NSMutableArray alloc] init];
    NSMutableArray *notMatched = [[NSMutableArray alloc] init];
    NSMutableArray *remoteResults = [remote mutableCopy];
    
    for (NSManagedObject *localResult in localResults) {
        BOOL didMatch = NO;
        
        for (NSDictionary *remoteResult in remoteResults) {
            NSNumber *localId = [localResult valueForKey:ZMIDKey];
            NSNumber *remoteId = [remoteResult valueForKey:ZMIDKey];
            
            if ([localId isEqualToNumber:remoteId]) {
                [self mergeLocal:localResult andRemote:remoteResult];
                [matched addObject:remoteResult];
                didMatch = YES;
            }
        }
        
        if (didMatch == NO) {
            NSNumber *state = [localResult valueForKey:ZMSyncStatusKey];
            
            if ([state isEqual: @(ZMSyncStateCreated)]){
                // populate a collection of records that exist locally, but not in the server.
                [notMatched addObject:localResult];
            }
            else {
                // if not in create state, delete it - it's gone!
                [deletions addObject:localResult];
            }
        }
        
        while (matched.count > 0)
        {
            NSDictionary *lastMatch = [matched lastObject];
            [remoteResults removeObject:lastMatch];
            [matched removeLastObject];
        }
    }
    
    for (NSDictionary *newRecord in remoteResults) {
        [creations addObject:newRecord];
    }
}

+ (void) mergeLocal:(NSManagedObject *) local andRemote: (NSDictionary *) remote
{
    NSNumber *state = [local valueForKey:ZMSyncStatusKey];

    if ([state isEqual: @(ZMSyncStateUpdated)]) {
        // Rule, if local syncTag == remote syncTag, local gets to overwrite. Otherwise it loses.
        NSString *localSyncTag = nil;
        // only use sync tag if the entity has one
        if ([[local.entity propertiesByName] objectForKey:ZMSyncTagKey]) {
            localSyncTag = [local valueForKey:ZMSyncTagKey];
        }
        
        if (localSyncTag == nil && [remote valueForKey:ZMSyncTagKey] == nil) {
            // this table isn't setup to use SyncTags, local wins
            return;
        }
        
        NSString *remoteSyncTag = [remote valueForKey:ZMSyncTagKey];
        if ([localSyncTag isEqualToString:remoteSyncTag] || (localSyncTag == nil && remoteSyncTag == nil)) {
            // Note this isn't a lasting change being made here, this will happen at sync time
            // we are just portraying this clients view of the world
            // However, theres is no point upating the (non mutable) remote record
            // we just don't use it. The local
            //[ZMTableSync mergeEntity:local onDictionary:remote];
            return;
        }
    }
    
    // if we get here, either the syncstate is 'synced' and we're just going to take the server
    // view of the world. Or the server has more recent data anyway.
    
    //ou we have no interesting changes to sync, server wins - just keeping local up to date
    [ZMTableSync mergeDictionary:remote onEntity:local];
}

- (void) dispatchSaveAsync
{
    if (self.isDirty == NO) {
        return;
    }
    dispatch_queue_t dispatcher = dispatch_get_main_queue();
    dispatch_async(dispatcher, ^{
        NSError *error;
        [self.context save:&error];
        if (!error) {
            self.isDirty = NO;
        }
        // TODO - record or handle the error
    });
}

@end
