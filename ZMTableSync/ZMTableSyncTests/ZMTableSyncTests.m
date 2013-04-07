//
//  ZMTableSyncTests.m
//  ZMTableSyncTests
//
//  Created by Josh Twist on 1/22/13.
//

#import "ZMTableSyncTests.h"
#import "ZMLocalStore.h"
#import <CoreData/CoreData.h>
#import <WindowsAzureMobileServices/WindowsAzureMobileServices.h>
#import "OCMockObject.h"
#import "OCMArg.h"
#import "OCMockRecorder.h"
#import "ZMAsyncTestingBlock.h"
#import "ZMTableSync.h"


@interface ZMTableSyncTests ()

@property (strong, nonatomic) NSManagedObjectContext *context;

@end

@implementation ZMTableSyncTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
    ZMLocalStore *store = [[ZMLocalStore alloc] init];
    self.context = store.managedObjectContext;
}

- (void)tearDown
{
    // Tear-down code here.
    
    NSArray *stores = [self.context.persistentStoreCoordinator persistentStores];
    
    for(NSPersistentStore *store in stores) {
        [self.context.persistentStoreCoordinator removePersistentStore:store error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:store.URL.path error:nil];
    }
    
    [super tearDown];
}

- (void) testQueryCachesToLocalDatabase
{
    ZMAsyncTestingBlock *atb = [[ZMAsyncTestingBlock alloc] init];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"id = 10"];
    
    NSArray *results = @[@{ @"id" : @10 }];
    
    // id mockTable = [self prepareMockTableWithResults:results count:-1 error:nil];
    
    id mockTable = [OCMockObject mockForClass:[MSTable class]];
    id mockQuery = [OCMockObject niceMockForClass:[MSQuery class]];
    
    [[[mockTable stub] andReturn:mockQuery] queryWhere:OCMOCK_ANY];
    
    [[mockQuery expect] readWithCompletion:[OCMArg checkWithBlock:^BOOL(id value) {
        MSReadQueryBlock block = (MSReadQueryBlock) value;
        [atb dispatch:^{
            block(results, -1, nil);
        }];
        return YES;
    }]];

    // The first read should load from the remote and populate the core data store
    ZMTableSync *target = [ZMTableSync tableSyncWithTable:mockTable entity:@"TestEntity" context:self.context];
    [target readWithPredicate:predicate sortDescriptors:nil completion:^(NSArray *results, NSError *error) {
        STAssertEqualObjects(@([results count]), @1, @"The array should contain a single record");
        STAssertEqualObjects([[results objectAtIndex:0] valueForKey:@"id"], @10, @"The id of the first result did not match that returned from the mock service");
    }];
    
    // The second read we want only the local results
    NSArray *localResults = [target readWithPredicate:predicate sortDescriptors:nil completion:nil];
    
    STAssertEqualObjects(@([localResults count]), @0, @"There should be no results in immediate local cache");

    [atb runToCompletion];

    [mockTable verify];
}

- (void) testMergeToDeleteLocal
{
    ZMAsyncTestingBlock *atb = [[ZMAsyncTestingBlock alloc] init];
    
    // This test ensures that we 
    
    NSArray *results = @[@{ @"id" : @1 }];
    
    id mockTable = [OCMockObject mockForClass:[MSTable class]];
    id mockQuery = [OCMockObject niceMockForClass:[MSQuery class]];
    
    [[[mockTable stub] andReturn:mockQuery] queryWhere:OCMOCK_ANY];
    
    [[mockQuery expect] readWithCompletion:[OCMArg checkWithBlock:^BOOL(id value) {
        MSReadQueryBlock block = (MSReadQueryBlock) value;
        [atb dispatch:^{
            block(results, -1, nil);
        }];
        return YES;
    }]];
    
    ZMTableSync *target = [ZMTableSync tableSyncWithTable:mockTable entity:@"TestEntity" context:self.context];
    
    // prepopulate the local core data database
    [[target createEntity] setValue:@1 forKey:@"id"]; // this record should remain
    [[target createEntity] setValue:@2 forKey:@"id"]; // this record should be deleted
    
    NSArray *localResults = [target readWithPredicate:nil sortDescriptors:nil completion:^(NSArray *results, NSError *error) {
        STAssertTrue([results count] == 1, @"The count of results should be 3");
        STAssertEqualObjects([[results objectAtIndex:0] valueForKey:@"id"], @1, @"id of the only object should be 1");
    }];
    
    STAssertTrue([localResults count] == 2, @"There should be 2 results, before the remote results cause deletion of a local record");
    
    [atb runToCompletion];
    
    [mockTable verify];
}

- (void) testMergeToIncludeLocalCreatedOnly
{
    ZMAsyncTestingBlock *atb = [[ZMAsyncTestingBlock alloc] init];
    
    // This test ensures that we
    
    NSArray *results = @[@{ @"id" : @1 }];
    
    id mockTable = [OCMockObject mockForClass:[MSTable class]];
    id mockQuery = [OCMockObject niceMockForClass:[MSQuery class]];
    
    [[[mockTable stub] andReturn:mockQuery] queryWhere:OCMOCK_ANY];
    
    [[mockQuery expect] readWithCompletion:[OCMArg checkWithBlock:^BOOL(id value) {
        MSReadQueryBlock block = (MSReadQueryBlock) value;
        [atb dispatch:^{
            block(results, -1, nil);
        }];
        return YES;
    }]];
    
    ZMTableSync *target = [ZMTableSync tableSyncWithTable:mockTable entity:@"TestEntity" context:self.context];
    
    NSManagedObject *new = [target createEntity];
    [new setValue:@2 forKey:@"id"];
    [new setValue:@(ZMSyncStateCreated) forKey:@"SyncStatus"];
    
    NSManagedObject *new2 = [target createEntity];
    [new2 setValue:@3 forKey:@"id"];
    [new2 setValue:@(ZMSyncStateUpdated) forKey:@"SyncStatus"];
    
    NSManagedObject *new3 = [target createEntity];
    [new3 setValue:@4 forKey:@"id"];
    [new3 setValue:@(ZMSyncStateDeleted) forKey:@"SyncStatus"];
    
    NSArray *local = [target readWithPredicate:nil sortDescriptors:nil completion:^(NSArray *results, NSError *error) {
        STAssertEqualObjects(@([results count]), @2, @"There should be two items after merge");
        STAssertEqualObjects(@([[results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == 1"]] count]), @1, @"should be one item with id == 1");
        STAssertEqualObjects(@([[results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == 2"]] count]), @1, @"should be one item with id == 2");
        STAssertNotNil(new.managedObjectContext, @"new should still be attached to the context");
        STAssertNil(new3.managedObjectContext, @"new3 should be deleted");
        STAssertNil(new2.managedObjectContext, @"new2 should be deleted");
        
    }];
    
    STAssertEqualObjects(@([local count]), @2, @"There should be two (no deleted) in original results");
    STAssertEqualObjects(@([self countInArray:local matchingPredicate:@"id == 2"]), @1, @"1 record with id 1 (created)");
    STAssertEqualObjects(@([self countInArray:local matchingPredicate:@"id == 3"]), @1, @"1 record with id 3 (updated)");
    STAssertEqualObjects(@([self countInArray:local matchingPredicate:@"id == 4"]), @0, @"No records with id 3 (deleted)");
    
    [atb runToCompletion];
    
    [mockTable verify];
}

- (void) testLocalUpdatedAndDeletedOverridesRemote
{
    ZMAsyncTestingBlock *atb = [[ZMAsyncTestingBlock alloc] init];
    
    // This test ensures that we
    
    NSArray *results = @[@{ @"id" : @1, @"age" : @10 }, @{ @"id" : @2, @"age" : @10 }];
    
    id mockTable = [OCMockObject mockForClass:[MSTable class]];
    id mockQuery = [OCMockObject niceMockForClass:[MSQuery class]];
    
    [[[mockTable stub] andReturn:mockQuery] queryWhere:OCMOCK_ANY];
    
    [[mockQuery expect] readWithCompletion:[OCMArg checkWithBlock:^BOOL(id value) {
        MSReadQueryBlock block = (MSReadQueryBlock) value;
        [atb dispatch:^{
            block(results, -1, nil);
        }];
        return YES;
    }]];
    
    ZMTableSync *target = [ZMTableSync tableSyncWithTable:mockTable entity:@"TestEntity" context:self.context];
    
    id new = [target createEntity];
    [new setValue:@1 forKey:@"id"];
    [new setValue:@20 forKey:@"age"];
    [new setValue:@(ZMSyncStateUpdated) forKey:@"SyncStatus"];
    
    id new2 = [target createEntity];
    [new2 setValue:@2 forKey:@"id"];
    [new2 setValue:@(ZMSyncStateDeleted) forKey:@"SyncStatus"];
    
    [target readWithPredicate:nil sortDescriptors:nil completion:^(NSArray *results, NSError *error) {
        STAssertEqualObjects(@([results count]), @1, @"There should be one item after merge");
        STAssertEqualObjects([[results objectAtIndex:0] valueForKey:@"id"], @1, @"object id 1 should be the only visible");
        STAssertEqualObjects([[results objectAtIndex:0] valueForKey:@"age"], @20, @"Age should be 20, local update wins");
    }];
    
    [atb runToCompletion];
    
    [mockTable verify];
}

- (void) testSyncTagCollisionDetection
{
    ZMAsyncTestingBlock *atb = [[ZMAsyncTestingBlock alloc] init];
    
    // This test ensures that we
    
    NSArray *results = @[@{ @"id" : @1, @"age" : @10, @"syncTag": @"abc" }, @{ @"id" : @2, @"age" : @10, @"syncTag" : @"def" }];
    
    id mockTable = [OCMockObject mockForClass:[MSTable class]];
    id mockQuery = [OCMockObject niceMockForClass:[MSQuery class]];
    
    [[[mockTable stub] andReturn:mockQuery] queryWhere:OCMOCK_ANY];
    
    [[mockQuery expect] readWithCompletion:[OCMArg checkWithBlock:^BOOL(id value) {
        MSReadQueryBlock block = (MSReadQueryBlock) value;
        [atb dispatch:^{
            block(results, -1, nil);
        }];
        return YES;
    }]];
    
    ZMTableSync *target = [ZMTableSync tableSyncWithTable:mockTable entity:@"TestEntityWithTag" context:self.context];
    
    id new = [target createEntity];
    [new setValue:@1 forKey:@"id"];
    [new setValue:@20 forKey:@"age"];
    [new setValue:@"abc" forKey:@"syncTag"];
    [new setValue:@(ZMSyncStateUpdated) forKey:@"syncStatus"];
    
    id new2 = [target createEntity];
    [new2 setValue:@2 forKey:@"id"];
    [new2 setValue:@20 forKey:@"age"];
    [new2 setValue:@"something-else" forKey:@"syncTag"];
    [new2 setValue:@(ZMSyncStateUpdated) forKey:@"syncStatus"];
    
    [target readWithPredicate:nil sortDescriptors:nil completion:^(NSArray *results, NSError *error) {
        STAssertEqualObjects(@([results count]), @2, @"There should be two items after merge");
        STAssertEqualObjects([[[results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == 1"]] objectAtIndex:0] valueForKey:@"age"], @20, @"object with id 1 should take local value");
        STAssertEqualObjects([[[results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"id == 2"]] objectAtIndex:0] valueForKey:@"age"], @10, @"object with id 2 should take remote value");
    }];
    
    [atb runToCompletion];
    
    [mockTable verify];
}

- (void) testRemoteErrorDoesNotTouchCache
{
    ZMAsyncTestingBlock *atb = [[ZMAsyncTestingBlock alloc] init];
    
    // This test ensures that we
    
    id mockTable = [OCMockObject mockForClass:[MSTable class]];
    id mockQuery = [OCMockObject niceMockForClass:[MSQuery class]];
    
    [[[mockTable stub] andReturn:mockQuery] queryWhere:OCMOCK_ANY];
    
    [[mockQuery expect] readWithCompletion:[OCMArg checkWithBlock:^BOOL(id value) {
        MSReadQueryBlock block = (MSReadQueryBlock) value;
        [atb dispatch:^{
            block(nil, -1, [NSError errorWithDomain:@"foo" code:2234 userInfo:nil]);
        }];
        return YES;
    }]];
    
    ZMTableSync *target = [ZMTableSync tableSyncWithTable:mockTable entity:@"TestEntity" context:self.context];
    
    id new = [target createEntity];
    [new setValue:@1 forKey:@"id"];
    id new2 = [target createEntity];
    [new2 setValue:@2 forKey:@"id"];
    
    [target readWithPredicate:nil sortDescriptors:nil completion:^(NSArray *results, NSError *error) {
        STAssertEqualObjects(error.domain, @"foo", @"Error code should match");
        STAssertEqualObjects(@([results count]), @0, @"There should be two items after merge");
    }];
    
    NSArray *local = [target readWithPredicate:nil sortDescriptors:nil completion:nil];
    STAssertEqualObjects(@([local count]), @2, @"There should still be 2 records in local cache");
    
    [atb runToCompletion];
    
    [mockTable verify];
}

- (int) countInArray:(NSArray *) array matchingPredicate:(NSString *) predicate
{
    NSArray *results = [array filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:predicate]];
    return [results count];
}

@end
