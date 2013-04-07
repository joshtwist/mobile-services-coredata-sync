# Mobile Services & Core Data Sync

[Windows Azure Mobile Services](http://www.windowsazure.com/ios) provides an easy way to store data in the Windows Azure cloud with a native [iOS SDK]. Many applications need to access data when not connected to the cloud. This project was used in the [doto](http://doto.mobi) iOS application to provide a simple offline capability and is shared here for others to use. It was created as part of a hobby project and should be considered experimental and looking forward to active feedback and participation from the community!

The approach to offline taken by this library is simple and affords much control to the consuming developer. It does not attempt to create a merge replication style synchronization capability but is based around the idea of a simple _local reference cache_ and _store and forward_ pattern for changes. 

Data is stored in a local Core Data database and this must be manually configured beforehand for use.

## Setup

To use this library you must first configure your core data database with each table you would like to sync to Mobile Services. The table in Core Data does not have to have the same name as the table in Mobile Services but this makes things easier to follow. 

The only pre-requisites that this library imposes on your Core Data schema are:

1. Each entity must have an **id** property of type _Integer 32_
2. Each entity must have a **syncStatus** property of type _string_

The first is a pre-requisite for all objects in Windows Azure Mobile Services storage. The latter is used to indicate the state of the local record and whether it has changed since the last read or sync.

## Code

The **ZMSyncTable** class wraps the MSTable class that you will find in the Mobile Services iOS client SDK.

	MSClient *client = [MSClient clientWithApplicationUrlString:@"<Your Mobile Services Url>" applicationKey:@"<Your Mobile Services Key>"];

	MSTable *example = [client tableWithName:@"example"];

	ZMTableSync *syncedTable = [ZMTableSync tableSyncWithTable:example entity:@"entityName" context:managedObjectContext];

The **syncedTable** instance is now a proxy to both the Mobile Service and your Core Data table.

#Modifying Data
Calling the insert, update or delete methods on the ZMSyncTable instance will instantly write that change ot the local Core Data database (with syncStatus property of ZMSyncStatusCreated, Updated or Deleted as appropriate). In parallel, ZMSyncTable will also try to write the change to the Mobile Service data table. 

Note that ZMSyncTable contains no knowledge about network connectivity. Instead, if the network is not present, the insert call will return an error. The developer can choose to ignore this, safe in the knowledge that the change is stored in the local DB and can be synced later via the **sync** method.

To insert a new object, you must create an instance of an NSManagedObject affiliated with your Core Data table. A convenience method is provided on the ZMTableSync instance:

	NSManagedObject *foo = [syncedTable createEntity];

This can then be populated with data and uploaded to the Mobile Service using the insert method. You can also cast to your subclass of NSManagedObject:

	MYFoo *foo = (*MYFoo) [syncedTable createEntity];
	foo.thing = @"something";
	foo.wow = 90;

	// save to Mobile Services
	[syncedTable insert:foo completion:^(NSManagedObject* entity, NSError *error){ 
		// if successful, entity will contain
		// an updated NSManagedObject with a populated
		// id property. If there was an error,
		// the error object will contain details
		// otherwise it should be nil
	}];

> It is important to note that since the actual NSManagedObject is exposed directly to you, it is possible to make changes that will be persisted to the Core Data database without the ZMSyncTable being aware of this. It is extremely important that after any changes are made to a synced object the appropriate **insert** or **update** methods are invoked so that the syncStatus is updated appropriately. 

## Reading Data

Whenever the ZMSyncTable instance is used to query data, all results from Mobile Services are stored in the Core Data database. Also, the query mechanism always returns the results from the Core Data database instantly, e.g.

	// localResults are returned synchronously from the
	// Core Data database
	NSArray *localResults = [syncedTable readWithPredicate:nil completion:^(NSArray *remoteResults, NSError *error) {
		// This will read all results from the database
		// once this callback is invoked, the core data 
		// database shoud have been updated.
		// If there was an error (e.g. no connectivity)
		// you can swallow that here and just use the
		// localResults instead
	}];

The localResults array is returned 'immediately' and can be used to show data to users with a tiny delay before updating with more _live_ results. Also, the localResults should be used in the event that data can't be retrieved from Mobile Services (e.g. due to the lack of a connection).

## Syncing local changes
After a period of disconnectivity, you will need to programmatically upload any changes to the Mobile Service. To trigger a sync (all changes) from the local database call the **synchronizeLocalChangesWithCallback** method. The callback will be invoked multiple times, once for every entity updated. 

	[syncedTable synchronizeLocalChangesWithCallback:^(ZMSyncOperationType operation, NSManagedObject *entity, NSDictionary *remote, NSError *error){
		// operation - indicates the type of operation
		// that was performed: insert, update, delete
		// remote - provides a copy of the new, updated object
		// error - nil unless something went wrong.
	}];
	
Note that if a sync fails for a single entity, the error parameter will be populated and this object will still be marked as _not synchronized_ 

> **NOTE** This is not a tutorial on Core Data. You should familiarize yourself with the basics of Core Data before trying to use this library.

### FAQ
**What about relationships?** Mobile Services does not attempt to create an ORM and there is no support currently for relationships. Therefore relationships are not recommended in the CoreData data structure either.

**What about concurrency?** The current implementation offers no advanced concurrency support. There is some support for optimistic concurrency but it is not fully documented as it requires improvement. To activate this feature you should add a syncTag property to your entity's schema and populate this value on your **insert** and **update** server scripts:

		function insert(item, user, request) {
			// create some unique stamp - time is good
			item.syncTag = new Date().getTime().toString();
			request.execute();
		}

		function update(item, user, request) {
			// update the unique stamp
			item.syncTag = new Date().getTime().toString();
			request.execute();
		}

**How reliable is this?** This is code you took from a bathroom wall - it works well in [doto](http://doto.mobi) but you use at your own risk. Pull Requests are happily considered #youtakeit

**Why are the local results returned synchronously?** Ideally this should be changed to read from Core Data asynchronously. #youtakeit

**What about unit tests?** Some 'unit' (mostly integration) tests are included in the repo but coverage could be improved - especially for the insert, update and delete methods. #youtakeit

**Why so few query methods?** Doto limits the number of items returned so advanced query options like pagination etc are not required. Adding more options for query should be added to the backlog. #youtakeit

**What about massive volumes of data?** The library has only been tested with small (<1000 records per table) volumes of data and has not been designed for synchronizing very large data volumes.