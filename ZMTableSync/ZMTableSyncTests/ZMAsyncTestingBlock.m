//
//  AsyncTestingBlock.m
//  ZumoSync
//
//  Created by Josh Twist on 2/3/13.
//

#import "ZMAsyncTestingBlock.h"

@interface ZMAsyncTestingBlock ()

@property (nonatomic)   dispatch_queue_t queue;
@property (nonatomic)   int count;

@end

@implementation ZMAsyncTestingBlock

- (id)init
{
    self = [super init];
    
    self.queue = dispatch_get_current_queue();
    
    return self;
}


- (void)dispatch:(void (^)())block
{
    self.count++;
    dispatch_async(self.queue, ^{
        block();
        self.count--;
    });
}

- (void)runToCompletion
{
    while (self.count > 0 && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}

@end
