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

#import "FRFolderViewController.h"
#import "FRFolder.h"
#import "FRMessage.h"
#import "FRPerson.h"

@interface FRFolderViewController () <NSFetchedResultsControllerDelegate> {
    NSArray *searchResults;
    BOOL isSearching;
}
@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@end

@implementation FRFolderViewController

@synthesize fetchedResultsController;
@synthesize folder;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *title = [self.folder.name stringByAppendingFormat:@" (%tu)",
                       [[self.fetchedResultsController fetchedObjects] count]];
    [self setTitle:title];
}

#pragma mark - Search Controller

- (void)updateSearchForController:(UISearchDisplayController *)controller {
    
    NSString *searchString = controller.searchBar.text;
    NSManagedObjectContext *context = self.folder.managedObjectContext;
    NSEntityDescription *entity =
        [NSEntityDescription entityForName:@"Message"
                    inManagedObjectContext:context];
    NSSortDescriptor *dateSort =
        [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO];
    NSPredicate *predicate = nil;
    
    if (controller.searchBar.selectedScopeButtonIndex == 0) {
        predicate = [NSPredicate predicateWithFormat:@"subject contains[cd] %@",
                     searchString];
    }
    else if (controller.searchBar.selectedScopeButtonIndex == 1) {
        predicate = [NSPredicate predicateWithFormat:
                     @"sender.name contains[cd] %@ or "
                     @"sender.email contains[cd] %@",
                     searchString, searchString];
    }
    else if (controller.searchBar.selectedScopeButtonIndex == 2) {
        predicate = [NSPredicate predicateWithFormat:@"subquery(recipients, $r, "
                     @"$r.name contains[cd] %@ or "
                     @"$r.email contains[cd] %@) != 0",
                     searchString, searchString];
    }
    
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:entity];
    [fetchRequest setPredicate:
     [NSCompoundPredicate andPredicateWithSubpredicates:
      [NSArray arrayWithObjects:
       self.fetchedResultsController.fetchRequest.predicate, predicate, nil]]];
    [fetchRequest setSortDescriptors:
     [NSArray arrayWithObjects:dateSort, nil]];

    searchResults = [context executeFetchRequest:fetchRequest error:NULL];
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller
shouldReloadTableForSearchScope:(NSInteger)searchOption {
    [self updateSearchForController:controller];
    return YES;
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller
shouldReloadTableForSearchString:(NSString *)searchString {
    [self updateSearchForController:controller];
    return YES;
}


#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        return 1;
    }
    return [[self.fetchedResultsController sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        return isSearching ? 1 : [searchResults count];
    }

    id <NSFetchedResultsSectionInfo> sectionInfo =
    [[self.fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (tableView == self.searchDisplayController.searchResultsTableView && isSearching) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"search"];
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"search"];
        cell.textLabel.text = NSLocalizedString(@"Searching", nil);
        cell.textLabel.textAlignment = UITextAlignmentCenter;
        cell.textLabel.textColor = [UIColor grayColor];
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"cell"];
    }
    [self configureCell:cell atIndexPath:indexPath inTableView:tableView];
    return cell;
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style
forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (style == UITableViewCellEditingStyleDelete) {
        NSFetchedResultsController *controller = self.fetchedResultsController;
        NSManagedObjectContext *context = [controller managedObjectContext];
        [context deleteObject:[self.fetchedResultsController objectAtIndexPath:indexPath]];
        
        NSError *error = nil;
        if (![context save:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }   
}

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

#pragma mark - Fetched results controller

- (NSFetchedResultsController *)fetchedResultsController {
    if (fetchedResultsController != nil) {
        return fetchedResultsController;
    }
    
    NSManagedObjectContext *context = self.folder.managedObjectContext;
    
    NSEntityDescription *entity =
        [NSEntityDescription entityForName:@"Message"
                    inManagedObjectContext:context];
    NSSortDescriptor *dateSort =
        [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setPredicate:
     [NSPredicate predicateWithFormat:@"folder = %@", self.folder]];
    [fetchRequest setRelationshipKeyPathsForPrefetching:
     [NSArray arrayWithObjects:@"sender", nil]];
    [fetchRequest setEntity:entity];
    [fetchRequest setFetchBatchSize:20];
    [fetchRequest setSortDescriptors:
     [NSArray arrayWithObjects:dateSort, nil]];
    
    fetchedResultsController =
        [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                            managedObjectContext:context
                                              sectionNameKeyPath:nil
                                                       cacheName:nil];
    fetchedResultsController.delegate = self;
    
    NSError *error = nil;
    if (![fetchedResultsController performFetch:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    
    return fetchedResultsController;
}    

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type {
    
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex]
                          withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex]
                          withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {
    
    UITableView *tableView = self.tableView;
    
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeUpdate:
            [self configureCell:[tableView cellForRowAtIndexPath:indexPath]
                    atIndexPath:indexPath
                    inTableView:tableView];
            break;
            
        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
          inTableView:(UITableView *)tableView {
    if (tableView == self.searchDisplayController.searchResultsTableView) {
        FRMessage *message = [searchResults objectAtIndex:indexPath.row];
        cell.textLabel.text = message.subject;
        cell.detailTextLabel.text = [message.sender.email description];
        return;
    }
    FRMessage *message = [self.fetchedResultsController objectAtIndexPath:indexPath];
    cell.textLabel.text = message.subject;
    cell.detailTextLabel.text = [message.sender.email description];
}

@end
