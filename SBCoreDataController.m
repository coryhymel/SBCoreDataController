//
//  SBCoreDataController.m
//  SBCoreDataControllerExample
//
//  Created by Cory Hymel on 4/14/14.
//  Copyright (c) 2014 Simble. All rights reserved.
//

#import "SBCoreDataController.h"

static dispatch_queue_t coredata_background_save_queue;

@interface SBCoreDataController () {
    NSURL *dbStoreURL;
}

@property (strong, nonatomic) NSManagedObjectContext *masterManagedObjectContext;
@property (strong, nonatomic) NSManagedObjectContext *backgroundManagedObjectContext;
@property (strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@end

@implementation SBCoreDataController

@synthesize masterManagedObjectContext = _masterManagedObjectContext;
@synthesize backgroundManagedObjectContext = _backgroundManagedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

+ (id)sharedInstance {
    static dispatch_once_t once;
    static SBCoreDataController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

- (void)initilizeDatabase:(void (^)())completion {
    
    [self performSelectorOnMainThread:@selector(persistentStoreCoordinator) withObject:nil waitUntilDone:YES];
    [self performSelectorOnMainThread:@selector(masterManagedObjectContext) withObject:nil waitUntilDone:YES];
    [self performSelectorOnMainThread:@selector(backgroundManagedObjectContext) withObject:nil waitUntilDone:YES];
    
    if (completion)
        completion();
}


#pragma mark - Core Data helpers

- (NSManagedObject*)fetchNSManagedObject:(NSManagedObjectID*)managedObjectID {
    
    NSManagedObjectContext *fetchContext = [self newManagedObjectContext];
    
    __block NSManagedObject *returnObject;
    __block NSError *error;
    
    [fetchContext performBlockAndWait:^{
        returnObject = [fetchContext existingObjectWithID:managedObjectID error:&error];
    }];
    
    if (error) {
        NSLog(@"Error fetching NSManagedObject: %@", error.localizedDescription);
        return nil;
    }
    
    else
        return returnObject;
}

#pragma mark - Core Data stack

/*
 
 New as of 12.3.13
 Convience methods for saving in the background
 Not fully tested
 
 
 Example usage:
 
 NSArray *listOfPeople = ...;
 
 [NSManagedObjectHelper saveDataInBackgroundWithContext:^(NSManagedObjectContext *localContext){
 for (NSDictionary *personInfo in listOfPeople)
 {
 PersonEntity *person = [PersonEntity createInContext:localContext];
 [person setValuesForKeysWithDictionary:personInfo];
 }
 } completion:^{
 self.people = [PersonEntity findAll];
 }];
 */

//
// -------- BEGIN ---------
//
- (void)saveDataInContext:(void(^)(NSManagedObjectContext *context))saveBlock
{
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	
    [context setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    
    [self.masterManagedObjectContext setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
    
	[context setParentContext:self.masterManagedObjectContext];
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	[notificationCenter addObserver:self
                           selector:@selector(backgroundDidSaveNotification:)
                               name:NSManagedObjectContextDidSaveNotification
                             object:context];
    
	saveBlock(context);
	
    if ([context hasChanges])
	{
		NSError *error;
        if (![context save:&error]) {
            NSAssert(error, @"Error saving data:\n ---%@\n ---%@", error, error.localizedDescription);
        }
	}
}

- (void)saveDataInBackgroundWithContext:(void(^)(NSManagedObjectContext *context))saveBlock completion:(void(^)(void))completion
{
    
    dispatch_async(coredata_background_save_queue, ^{
        
        [self saveDataInContext:saveBlock];
        
		dispatch_sync(dispatch_get_main_queue(), ^{
			completion();
		});
    });
}

dispatch_queue_t background_save_queue()
{
    if (coredata_background_save_queue == NULL)
    {
        coredata_background_save_queue = dispatch_queue_create("com.PNT.coredata.backgroundsaves", 0);
    }
    return coredata_background_save_queue;
}

//
// End untested code
// -------- END ---------
//

/**
 Merges the changes from a DidSaveNotification
 */
- (void)backgroundDidSaveNotification:(NSNotification*)notificaton {
    [self.masterManagedObjectContext mergeChangesFromContextDidSaveNotification:notificaton];
    [self saveMasterContext];
}

/*
 
 Invoked method from masterManagedObjectContext method on 1.14.14 changes. This is currently causing and error as of 1.14.14 and needs further investigation.
 
 - (void)masterDidSaveNotification:(NSNotification*)notification {
 [self.backgroundManagedObjectContext mergeChangesFromContextDidSaveNotification:notification];
 [self saveBackgroundContext];
 }
 */


// Used to propegate saves to the persistent store (disk) without blocking the UI
- (NSManagedObjectContext *)masterManagedObjectContext {
    if (_masterManagedObjectContext != nil) {
        return _masterManagedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _masterManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [_masterManagedObjectContext performBlockAndWait:^{
            
            [_masterManagedObjectContext setPersistentStoreCoordinator:coordinator];
            
            /*
             This causes:
             EXC_BAD_ACCESS error. Needs further investigation
             
             //
             //The following was added 1.14.14 and has not been fully tested
             //------Begin 1.14.14 additions ----
             NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
             [notificationCenter addObserver:self
             selector:@selector(masterDidSaveNotification:)
             name:NSManagedObjectContextDidSaveNotification
             object:_masterManagedObjectContext];
             //------End 1.14.14 additions -------
             */
            
        }];
        
    }
    return _masterManagedObjectContext;
}

// Return the NSManagedObjectContext to be used in the background during sync
- (NSManagedObjectContext *)backgroundManagedObjectContext {
    
    if (_backgroundManagedObjectContext != nil) {
        return _backgroundManagedObjectContext;
    }
    
    NSManagedObjectContext *masterContext = [self masterManagedObjectContext];
    
    if (masterContext != nil) {
        _backgroundManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        [_backgroundManagedObjectContext performBlockAndWait:^{
            
            [_backgroundManagedObjectContext setParentContext:masterContext];
            
            //
            //The following was added 1.14.14 and has not been fully tested
            //------Begin 1.14.14 additions ----
            NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
            [notificationCenter addObserver:self
                                   selector:@selector(backgroundDidSaveNotification:)
                                       name:NSManagedObjectContextDidSaveNotification
                                     object:_backgroundManagedObjectContext];
            //------End 1.14.14 additions -------
            
        }];
    }
    
    return _backgroundManagedObjectContext;
}

// Return the NSManagedObjectContext to be used in the background during sync
- (NSManagedObjectContext *)newManagedObjectContext {
    
    NSManagedObjectContext *newContext = nil;
    
    NSManagedObjectContext *masterContext = [self masterManagedObjectContext];
    
    if (masterContext != nil) {
        
        newContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        [newContext performBlockAndWait:^{
            [newContext setParentContext:masterContext];
            
            NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
            [notificationCenter addObserver:self
                                   selector:@selector(backgroundDidSaveNotification:)
                                       name:NSManagedObjectContextDidSaveNotification
                                     object:newContext];
        }];
    }
    
    return newContext;
}

- (void)saveMasterContext {
    [self.masterManagedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        BOOL saved = [self.masterManagedObjectContext save:&error];
        if (!saved) {
            // do some real error handling
            NSLog(@"Could not save master context due to %@", error);
        }
    }];
}

- (void)saveMasterContextWithBlock:(void(^)())completion {
    [self.masterManagedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        BOOL saved = [self.masterManagedObjectContext save:&error];
        if (!saved) {
            // do some real error handling
            NSLog(@"Could not save master context due to %@", error);
        }
        completion();
    }];
}

- (void)saveBackgroundContext {
    [self.backgroundManagedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        BOOL saved = [self.backgroundManagedObjectContext save:&error];
        if (!saved) {
            // do some real error handling
            NSLog(@"Could not save background context due to %@", error);
        }
    }];
}

- (void)saveBackgroundContextWithBlock:(void(^)())completion {
    [self.backgroundManagedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        BOOL saved = [self.backgroundManagedObjectContext save:&error];
        if (!saved) {
            // do some real error handling
            NSLog(@"Could not save background context due to %@", error);
            completion();
        } else
            completion();
    }];
}

- (void)saveMasterAndBackgroundContext {
    [self.backgroundManagedObjectContext performBlockAndWait:^{
        NSError *bgError = nil;
        BOOL saved = [self.backgroundManagedObjectContext save:&bgError];
        if (!saved) {
            // do some real error handling
            NSLog(@"Could not save background context due to %@", bgError);
        }
        
        [self.masterManagedObjectContext performBlockAndWait:^{
            NSError *msError = nil;
            BOOL saved = [self.masterManagedObjectContext save:&msError];
            if (!saved) {
                // do some real error handling
                NSLog(@"Could not save master context due to %@", msError);
            }
        }];
    }];
}

- (void)saveMasterAndBackgroundContextWithBlock:(void(^)())completion {
    [self.backgroundManagedObjectContext performBlockAndWait:^{
        NSError *bgError = nil;
        BOOL saved = [self.backgroundManagedObjectContext save:&bgError];
        if (!saved) {
            // do some real error handling
            NSLog(@"Could not save background context due to %@", bgError);
        }
        
        [self.masterManagedObjectContext performBlockAndWait:^{
            NSError *msError = nil;
            BOOL saved = [self.masterManagedObjectContext save:&msError];
            if (!saved) {
                // do some real error handling
                NSLog(@"Could not save master context due to %@", msError);
            }
            completion();
        }];
    }];
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"Renshaw" ofType:@"momd"];
    NSURL *modelURL = [NSURL fileURLWithPath:modelPath];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Renshaw.sqlite"];
    
    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    } else {
        // Store successfully created
        // Set exclude from iCloud backup flag on giant database file since we can always re-sync rather than restore from iCloud
        NSError *error = nil;
        BOOL success = [storeURL setResourceValue: [NSNumber numberWithBool: YES]
                                           forKey: NSURLIsExcludedFromBackupKey error: &error];
        if(!success){
            NSLog(@"Error excluding %@ from backup %@", [storeURL lastPathComponent], error);
        }
    }
    
    return _persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

@end
