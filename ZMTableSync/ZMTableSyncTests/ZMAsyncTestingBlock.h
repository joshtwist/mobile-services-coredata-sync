//
//  AsyncTestingBlock.h
//  ZumoSync
//
//  Created by Josh Twist on 2/3/13.
//

#import <Foundation/Foundation.h>

@interface ZMAsyncTestingBlock : NSObject

@property (nonatomic)    BOOL isComplete;

- (void) dispatch:(void (^)()) block;
- (void) runToCompletion;

@end
