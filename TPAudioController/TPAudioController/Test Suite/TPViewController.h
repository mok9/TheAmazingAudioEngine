//
//  TPViewController.h
//  Audio Controller Test Suite
//
//  Created by Michael Tyson on 13/02/2012.
//  Copyright (c) 2012 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TPAudioController;

@interface TPViewController : UITableViewController

@property (nonatomic, retain) TPAudioController *audioController;
@end