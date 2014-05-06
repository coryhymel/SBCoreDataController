//
//  SBCoreDataController.h
//  SBCoreDataControllerExample
//
//  Created by Cory Hymel on 4/14/14.
//  Copyright (c) 2014 Simble. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface SBCoreDataController : NSObject

+ (id)sharedInstance;

- (void)initilizeDatabase:(void(^)())completion;

- (NSURL *)applicationDocumentsDirectory;

- (NSManagedObject*)fetchNSManagedObject:(NSManagedObjectID*)managedObjectID;

- (NSManagedObjectContext *)masterManagedObjectContext;
- (NSManagedObjectContext *)backgroundManagedObjectContext;

/**
 Creates and returns a new NSManagedObjectContext with concurrency type NSPrivateQueueConcurrencyType. PNCoreDataController registers for NSManagedObjectContextDidSaveNotification on returned NSManagedObjectContext, when a save occurs, the new context will merge with master context. Master NSManagedObjectContext will then save.
 
 @note In the future it would be beneficial to add a parameter to this method allowing user to specify if they want the master NSManagedObjectContext to save automatically after merging changes.
 
 @return A new NSManagedObjectContext
 */
- (NSManagedObjectContext *)newManagedObjectContext;

- (NSManagedObjectModel *)managedObjectModel;
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;

- (void)saveMasterContext;
- (void)saveMasterContextWithBlock:(void(^)())completion;

- (void)saveBackgroundContext;
- (void)saveBackgroundContextWithBlock:(void(^)())completion;

- (void)saveMasterAndBackgroundContext;
- (void)saveMasterAndBackgroundContextWithBlock:(void(^)())completion;

/**
 Method to easily create a new NSManagedObjectContext for saving in the background
 
 @warning Untested as of 12.3.13 - Not recommended for production use
 
 @param saveBlock Returns a newly create NSManagedObjectContext for saving in the background. Perfrom any operations inside this block and they will be done in the background then merged to master context.
 @param completion Called when the save has finished.
 */
- (void)saveDataInBackgroundWithContext:(void(^)(NSManagedObjectContext *context))saveBlock completion:(void(^)(void))completion;


@end
