//
//  OCNewsHelper.m
//  iOCNews
//

/************************************************************************
 
 Copyright 2013 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCNewsHelper.h"
#import "Feeds.h"
#import "Feed.h"
#import "Item.h"

@implementation OCNewsHelper

@synthesize context;
@synthesize objectModel;
@synthesize coordinator;

+ (OCNewsHelper*)sharedHelper {
    static dispatch_once_t once_token;
    static id sharedHelper;
    dispatch_once(&once_token, ^{
        sharedHelper = [[OCNewsHelper alloc] init];
    });
    return sharedHelper;
}

- (OCNewsHelper*)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    Feeds *newFeeds = [NSEntityDescription insertNewObjectForEntityForName:@"Feeds" inManagedObjectContext:self.context];
    newFeeds.starredCount = [NSNumber numberWithInt:0];
    newFeeds.newestItemId = [NSNumber numberWithInt:0];
    
    NSError *saveError = nil;
    if ([self.context save:&saveError]) {
        NSLog(@"Feed saved");
    } else {
        NSLog(@"Error occured while saving");
        return nil;
    }

    return self;
}

- (NSManagedObjectModel *)objectModel {
    if (!objectModel) {
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"News" withExtension:@"momd"];
        objectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return objectModel;
}

- (NSPersistentStoreCoordinator *)coordinator {
    if (!coordinator) {
        NSURL *storeURL = [self documentsDirectoryURL];
        storeURL = [storeURL URLByAppendingPathComponent:@"News.sqlite"];
        
        NSError *error = nil;
        coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self objectModel]];
        if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
            NSLog(@"Error %@, %@", error, [error localizedDescription]);
            abort();
        }
    }
    return coordinator;
}

- (NSManagedObjectContext *)context {
    if (!context) {
        NSPersistentStoreCoordinator *myCoordinator = [self coordinator];
        if (myCoordinator != nil) {
            context = [[NSManagedObjectContext alloc] init];
            [context setPersistentStoreCoordinator:myCoordinator];
        }
    }
    return context;
}

- (void)saveContext {
    NSError *error = nil;
    if (context != nil) {
        if ([context hasChanges] && ![context save:&error]) {
            NSLog(@"Error %@, %@", error, [error userInfo]);
            //abort();
        }
    }
}

#pragma mark - COREDATA -INSERT

- (int)addFeed:(id)JSON {
    NSDictionary *jsonDict = (NSDictionary *) JSON;
    NSMutableArray *newFeeds = [jsonDict objectForKey:@"feeds"];
    NSDictionary *feed = [newFeeds lastObject];
    Feed *newFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
    newFeed.myId = [feed objectForKey:@"id"];
    newFeed.url = [feed objectForKey:@"url"];
    newFeed.title = [feed objectForKey:@"title"];
    id val = [feed objectForKey:@"faviconLink"];
    newFeed.faviconLink = (val == [NSNull null] ? @"favicon" : val);
    newFeed.added = [feed objectForKey:@"added"];
    newFeed.folderId = [feed objectForKey:@"folderId"];
    newFeed.unreadCount = [feed objectForKey:@"unreadCount"];
    newFeed.link = [feed objectForKey:@"link"];
    
    [self updateTotalUnreadCount];
    return newFeed.myIdValue;
}

- (void)deleteFeed:(Feed*)feed {
    NSFetchRequest *feedItemsFetcher = [[NSFetchRequest alloc] init];
    [feedItemsFetcher setEntity:[NSEntityDescription entityForName:@"Item" inManagedObjectContext:self.context]];
    [feedItemsFetcher setIncludesPropertyValues:NO];
    [feedItemsFetcher setPredicate:[NSPredicate predicateWithFormat:@"feedId == %@", feed.myId]];
    
    NSError *error = nil;
    NSArray *feedItems = [self.context executeFetchRequest:feedItemsFetcher error:&error];
    for (Item *item in feedItems) {
        [self.context deleteObject:item];
    }
    [self.context deleteObject:feed];
    [self updateTotalUnreadCount];
}

- (void)updateFeeds:(id)JSON {
    //Remove previous
    NSFetchRequest *oldFeedsFetcher = [[NSFetchRequest alloc] init];
    [oldFeedsFetcher setEntity:[NSEntityDescription entityForName:@"Feed" inManagedObjectContext:self.context]];
    [oldFeedsFetcher setIncludesPropertyValues:NO]; //only fetch the managedObjectID

    NSError *error = nil;
    NSArray *oldFeeds = [self.context executeFetchRequest:oldFeedsFetcher error:&error];
    
    
    NSLog(@"Count: %i", oldFeeds.count);
    
    for (NSManagedObject *feed in oldFeeds) {
        [self.context deleteObject:feed];
    }
    
    NSFetchRequest *feedsFetcher = [[NSFetchRequest alloc] init];
    [feedsFetcher setEntity:[NSEntityDescription entityForName:@"Feeds" inManagedObjectContext:self.context]];
    
    error = nil;
    NSArray *feeds = [self.context executeFetchRequest:feedsFetcher error:&error];
    
    //Add the new feeds
    NSDictionary *jsonDict = (NSDictionary *) JSON;
    Feeds *theFeeds = [feeds objectAtIndex:0];
    theFeeds.starredCount = [jsonDict objectForKey:@"starredCount"];
    theFeeds.newestItemId = [jsonDict objectForKey:@"newestItemId"];


    NSArray *newFeeds = [NSArray arrayWithArray:[jsonDict objectForKey:@"feeds"]];

    Feed *allFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
    allFeed.myId = [NSNumber numberWithInt:-2];
    allFeed.url = @"";
    allFeed.title = @"All Articles";
    allFeed.faviconLink = @"favicon";
    allFeed.added = [NSNumber numberWithInt:1];
    allFeed.folderId = [NSNumber numberWithInt:0];
    allFeed.unreadCount = [NSNumber numberWithInt:0];
    allFeed.link = @"";

    Feed *starredFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
    starredFeed.myId = [NSNumber numberWithInt:-1];
    starredFeed.url = @"";
    starredFeed.title = @"Starred";
    starredFeed.faviconLink = @"star_icon";
    starredFeed.added = [NSNumber numberWithInt:2];
    starredFeed.folderId = [NSNumber numberWithInt:0];
    starredFeed.unreadCount = theFeeds.starredCount;
    starredFeed.link = @"";
    
    [newFeeds enumerateObjectsUsingBlock:^(NSDictionary *feed, NSUInteger idx, BOOL *stop ) {
        Feed *newFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
        newFeed.myId = [feed objectForKey:@"id"];
        newFeed.url = [feed objectForKey:@"url"];
        newFeed.title = [feed objectForKey:@"title"];
        id val = [feed objectForKey:@"faviconLink"];
        newFeed.faviconLink = (val == [NSNull null] ? @"favicon" : val);
        newFeed.added = [feed objectForKey:@"added"];
        newFeed.folderId = [feed objectForKey:@"folderId"];
        newFeed.unreadCount = [feed objectForKey:@"unreadCount"];
        newFeed.link = [feed objectForKey:@"link"];
    }];
    
    [self updateTotalUnreadCount];
}

- (Feed*)feedWithId:(int)anId {
    NSDictionary *subs = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:anId] forKey:@"FEED_ID"];
    NSArray *myFeeds = [self.context executeFetchRequest:[self.objectModel fetchRequestFromTemplateWithName:@"feedWithIdRequest" substitutionVariables:subs] error:nil];
    return (Feed*)[myFeeds lastObject];
}

- (int)itemCount {
    NSFetchRequest *itemsFetcher = [[NSFetchRequest alloc] init];
    [itemsFetcher setEntity:[NSEntityDescription entityForName:@"Item" inManagedObjectContext:self.context]];
    [itemsFetcher setIncludesPropertyValues:NO]; //only fetch the managedObjectID
    
    NSError *error = nil;
    NSArray *items = [self.context executeFetchRequest:itemsFetcher error:&error];
    NSLog(@"Count: %i", items.count);
    return items.count;
}

- (void)updateItems:(NSArray*)items {
    if ([self itemCount] == 0) {
        //first time
        //Add the new items        
        [items enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
            Item *newItem = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:self.context];
            newItem.myId = [item objectForKey:@"id"];
            newItem.guid = [item objectForKey:@"guid"];
            newItem.guidHash = [item objectForKey:@"guidHash"];
            newItem.url = [item objectForKey:@"url"];
            newItem.title = [item objectForKey:@"title"];
            id val = [item objectForKey:@"author"];
            newItem.author = (val == [NSNull null] ? @"" : val);
            val = [item objectForKey:@"pubDate"];
            newItem.pubDate = (val == [NSNull null] ? nil : val);
            newItem.body = [item objectForKey:@"body"];
            val = [item objectForKey:@"enclosureMime"];
            newItem.enclosureMime = (val == [NSNull null] ? @"" : val);
            val = [item objectForKey:@"enclosureLink"];
            newItem.enclosureLink = (val == [NSNull null] ? @"" : val);
            newItem.feedId = [item objectForKey:@"feedId"];
            newItem.unread = [item objectForKey:@"unread"];
            newItem.starred = [item objectForKey:@"starred"];
            newItem.lastModified = [item objectForKey:@"lastModified"];
        }];

    } else {
        //updating
        __block NSMutableSet *possibleDuplicateItems = [NSMutableSet new];
        __block NSMutableSet *feedsWithNewItems = [NSMutableSet new];
        [items enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
            [possibleDuplicateItems addObject:[item objectForKey:@"guidHash"]];
            [feedsWithNewItems addObject:[item objectForKey:@"feedId"]];
        }];
        
        NSFetchRequest *itemsFetcher = [[NSFetchRequest alloc] init];
        [itemsFetcher setEntity:[NSEntityDescription entityForName:@"Item" inManagedObjectContext:self.context]];
        [itemsFetcher setIncludesPropertyValues:NO]; //only fetch the managedObjectID
        [itemsFetcher setPredicate:[NSPredicate predicateWithFormat: @"guidHash IN %@", possibleDuplicateItems]];

        NSError *error = nil;
        NSArray *duplicateItems = [self.context executeFetchRequest:itemsFetcher error:&error];
        NSLog(@"Count: %i", duplicateItems.count);

        for (NSManagedObject *item in duplicateItems) {
            [self.context deleteObject:item];
        }
        


        [items enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
            Item *newItem = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:self.context];
            newItem.myId = [item objectForKey:@"id"];
            newItem.guid = [item objectForKey:@"guid"];
            newItem.guidHash = [item objectForKey:@"guidHash"];
            newItem.url = [item objectForKey:@"url"];
            newItem.title = [item objectForKey:@"title"];
            id val = [item objectForKey:@"author"];
            newItem.author = (val == [NSNull null] ? @"" : val);
            newItem.pubDate = [item objectForKey:@"pubDate"];
            newItem.body = [item objectForKey:@"body"];
            val = [item objectForKey:@"enclosureMime"];
            newItem.enclosureMime = (val == [NSNull null] ? @"" : val);
            val = [item objectForKey:@"enclosureLink"];
            newItem.enclosureLink = (val == [NSNull null] ? @"" : val);
            newItem.feedId = [item objectForKey:@"feedId"];
            newItem.unread = [item objectForKey:@"unread"];
            newItem.starred = [item objectForKey:@"starred"];
            newItem.lastModified = [item objectForKey:@"lastModified"];
        }];
        
        NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"lastModified" ascending:NO];
        [itemsFetcher setSortDescriptors:[NSArray arrayWithObject:sort]];

        [feedsWithNewItems enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            [itemsFetcher setPredicate:[NSPredicate predicateWithFormat: @"feedId == %@", obj]];
            
            NSError *error = nil;
            NSArray *feedItems = [self.context executeFetchRequest:itemsFetcher error:&error];
            if (feedItems.count > 200) {
                NSLog(@"FeedId: %@; Count: %i", obj, feedItems.count);
                int i = feedItems.count;
                while (i > 200) {
                    Item *itemToRemove = [feedItems objectAtIndex:i - 1];
                    if (!itemToRemove.starredValue) {
                        [self.context deleteObject:itemToRemove];
                    }
                    --i;
                }
            }
        }];

    }
    
    [self updateTotalUnreadCount];
}

- (void)updateReadItems:(NSArray *)items {
    NSFetchRequest *itemsFetcher = [[NSFetchRequest alloc] init];
    [itemsFetcher setEntity:[NSEntityDescription entityForName:@"Item" inManagedObjectContext:self.context]];
    [itemsFetcher setPredicate:[NSPredicate predicateWithFormat: @"myId IN %@", items]];

    NSError *error = nil;
    NSArray *allItems = [self.context executeFetchRequest:itemsFetcher error:&error];
    if (!allItems || error) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    NSLog(@"Count: %i", items.count);
    
    [allItems enumerateObjectsUsingBlock:^(Item *item, NSUInteger idx, BOOL *stop) {
            item.unreadValue = NO;
            Feed *feed = [self feedWithId:item.feedIdValue];
            --feed.unreadCountValue;
    }];
    [self updateTotalUnreadCount];
}

- (void)updateTotalUnreadCount {
    NSArray *unreadFeeds = [self.context executeFetchRequest:[self.objectModel fetchRequestTemplateForName:@"totalUnreadRequest"] error:nil];
    __block int i = 0;
    [unreadFeeds enumerateObjectsUsingBlock:^(Feed *obj, NSUInteger idx, BOOL *stop) {
        if (obj.myIdValue >= 0) {
            i = i + obj.unreadCountValue;
        }
    }];
    [[self feedWithId:-2] setUnreadCountValue:i];
    NSError *error = nil;
    if ([self.context save:&error]) {
        NSLog(@"Feed saved");
    } else {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
}

- (void)updateStarredCount {
    NSFetchRequest *itemsFetcher = [[NSFetchRequest alloc] init];
    [itemsFetcher setEntity:[NSEntityDescription entityForName:@"Item" inManagedObjectContext:self.context]];
    [itemsFetcher setPredicate:[NSPredicate predicateWithFormat: @"starred == 1"]];
    
    NSError *error = nil;
    NSArray *starredItems = [self.context executeFetchRequest:itemsFetcher error:&error];
    if (!starredItems || error) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    NSLog(@"Count: %i", starredItems.count);
    
    NSFetchRequest *feedsFetcher = [[NSFetchRequest alloc] init];
    [feedsFetcher setEntity:[NSEntityDescription entityForName:@"Feeds" inManagedObjectContext:self.context]];
    
    error = nil;
    NSArray *feeds = [self.context executeFetchRequest:feedsFetcher error:&error];
    if (!feeds || error) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    Feeds *theFeeds = [feeds lastObject];
    theFeeds.starredCountValue = starredItems.count;
    
    [[self feedWithId:-1] setUnreadCountValue:starredItems.count];
    error = nil;
    if ([self.context save:&error]) {
        NSLog(@"Feed saved");
    } else {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
}

- (NSURL*) documentsDirectoryURL {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}


@end
