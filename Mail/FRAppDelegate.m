// 
// Copyright (c) 2012 Whitney Young
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:
// 
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
// 

#import "FRAppDelegate.h"
#import "FRMasterViewController.h"
#import "FRMessage.h"
#import "FRFolder.h"
#import "FRPerson.h"

static const BOOL kShouldResetData = FALSE;

@implementation FRAppDelegate

@synthesize window = window;
@synthesize managedObjectContext;
@synthesize managedObjectModel;
@synthesize persistentStoreCoordinator = persistentStoreCoordinator;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    UINavigationController *navigationController = (id)self.window.rootViewController;
    FRMasterViewController *controller = (id)navigationController.topViewController;
    controller.managedObjectContext = self.managedObjectContext;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [self saveContext];
}

- (void)saveContext {
    NSError *error = nil;
    NSManagedObjectContext *context = self.managedObjectContext;
    if ([context hasChanges] && ![context save:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    } 
}

#pragma mark - Syncing

- (IBAction)sync:(id)sender {
    NSManagedObjectContextConcurrencyType type = NSPrivateQueueConcurrencyType;
    NSManagedObjectContext *asyncContext =
        [[NSManagedObjectContext alloc] initWithConcurrencyType:type];
    
    // for large amounts of data, it will be slow to create a bunch of objects & the
    // actual save of that data to the disk will be even slower. therefore, it makes sense
    // to not use nested contexts here. a nested context would mean that the main thread
    // context would still block when actually writing out all of the new objects.
    asyncContext.persistentStoreCoordinator =
        self.managedObjectContext.persistentStoreCoordinator;

    // note that because we're doing this asynchronously, it's possible that we create
    // duplicate senders and/or folders.
    [asyncContext performBlock:^{
        NSURL *url = [NSURL URLWithString:@"http://localhost:8000/?count=150000"];
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];
        NSData *data = [NSURLConnection sendSynchronousRequest:request
                                             returningResponse:NULL error:NULL];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                             options:0 error:NULL];
        NSArray *messages = [json objectForKey:@"messages"];
        
        NSEntityDescription *messageEntity =
            [NSEntityDescription entityForName:@"Message"
                        inManagedObjectContext:asyncContext];
        NSEntityDescription *personEntity =
            [NSEntityDescription entityForName:@"Person"
                        inManagedObjectContext:asyncContext];
        NSEntityDescription *folderEntity =
            [NSEntityDescription entityForName:@"Folder"
                        inManagedObjectContext:asyncContext];
        
        // look for the inbox folder
        // typically it would be better to tag specalized folders with an integer,
        // but for simplicity, we'll just call the folder inbox & search by name.
        NSFetchRequest *folderRequest = [[NSFetchRequest alloc] init];
        [folderRequest setEntity:folderEntity];
        [folderRequest setPredicate:
         [NSPredicate predicateWithFormat:@"name = 'Inbox'"]];
        [folderRequest setFetchLimit:1];
        NSArray *folders = [asyncContext executeFetchRequest:folderRequest error:NULL];
        FRFolder *inbox = [folders lastObject];
        if (!inbox) {
            inbox = [[FRFolder alloc] initWithEntity:folderEntity
                       insertIntoManagedObjectContext:asyncContext];
            inbox.name = @"Inbox";
            inbox.index = 0;
        }
        
        // look up senders first so we don't have to do a fetch for each one.
        // note that even though this is a background context, the fetch will
        // block the main thread, so this would be very undesirable to do each
        // time through the loop.
        NSMutableDictionary *knownEmails = [NSMutableDictionary dictionary];
        NSFetchRequest *personRequest = [[NSFetchRequest alloc] init];
        [personRequest setEntity:personEntity];
        NSArray *people = [asyncContext executeFetchRequest:personRequest error:NULL];
        for (FRPerson *person in people) {
            [knownEmails setObject:person forKey:person.email];
        }

        for (NSDictionary *create in messages) {
            FRMessage *message = [[FRMessage alloc] initWithEntity:messageEntity
                                    insertIntoManagedObjectContext:asyncContext];
            
            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            [df setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
            
            message.body = [create objectForKey:@"body"];
            message.subject = [create objectForKey:@"subject"];
            message.date = [df dateFromString:[create objectForKey:@"date"]];
            
            // look for a sender with the email specified here
            NSString *senderEmail = [create objectForKey:@"sender"];
            FRPerson *sender = [knownEmails objectForKey:senderEmail];
            if (!sender) {
                sender = [[FRPerson alloc] initWithEntity:personEntity
                           insertIntoManagedObjectContext:asyncContext];
                sender.name = senderEmail;
                sender.email = senderEmail;
            }
            message.sender = sender;
            message.folder = inbox;
        }
        
        // observe saves so that we can merge changes into the main context
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        void (^observationBlock)(NSNotification *note) = nil;
        observationBlock = ^void(NSNotification *note) {
            NSManagedObjectContext *context = self.managedObjectContext;
            [context performBlock:^{
                [context mergeChangesFromContextDidSaveNotification:note];
            }];
        };
        id observer = [center addObserverForName:NSManagedObjectContextDidSaveNotification
                                          object:asyncContext queue:nil
                                      usingBlock:observationBlock];
        
        // save the context, changes will be merged into the main context
        [asyncContext save:NULL];
        
        // remove observer
        [center removeObserver:observer];
    }];
}

#pragma mark - Core Data stack

- (NSManagedObjectContext *)managedObjectContext {
    if (!managedObjectContext) {
        managedObjectContext =
            [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [managedObjectContext setPersistentStoreCoordinator:
         [self persistentStoreCoordinator]];
    }
    return managedObjectContext;
}

- (NSManagedObjectModel *)managedObjectModel {
    if (!managedObjectModel) {
        NSArray *bundles = [NSArray arrayWithObject:[NSBundle mainBundle]];
        managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:bundles];
    }
    return managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (!persistentStoreCoordinator) {
        NSURL *documents = [self applicationDocumentsURL];
        NSURL *storeURL = [documents URLByAppendingPathComponent:@"data.maildb"];
        NSManagedObjectModel *model = [self managedObjectModel];
        NSError *error = nil;
        
        NSURL *builtinData = [[NSBundle mainBundle] URLForResource:@"initial"
                                                     withExtension:@"maildb"];
        NSFileManager *manager = [NSFileManager defaultManager];
        if (kShouldResetData) {
            [manager removeItemAtURL:storeURL error:NULL];
        }
        if (![manager fileExistsAtPath:[storeURL path]] && builtinData) {
            [manager copyItemAtURL:builtinData toURL:storeURL error:NULL];
        }
        
        persistentStoreCoordinator =
            [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                        configuration:nil URL:storeURL
                                                            options:nil error:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
    return persistentStoreCoordinator;
}

- (NSURL *)applicationDocumentsURL {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *all = [manager URLsForDirectory:NSDocumentDirectory
                                   inDomains:NSUserDomainMask];
    return [all lastObject];
}

@end
