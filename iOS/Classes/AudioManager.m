//  AudioManager.m

#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import "AudioManager.h"
#import "Constants.h"
#import <AVFoundation/AVFoundation.h>

@interface AudioManager()
{
  STKAudioPlayer *audioPlayer;
  BOOL isPlayingWithOthers;
}
@end

@implementation AudioManager

@synthesize bridge = _bridge;

- (AudioManager *)init
{
  self = [super init];
  audioPlayer = [[STKAudioPlayer alloc] initWithOptions:(STKAudioPlayerOptions){ .readBufferSize = LPN_AUDIO_BUFFER_SEC }];
  [audioPlayer setDelegate:self];
  [self setSharedAudioSessionCategory];
  [self registerAudioInterruptionNotifications];
  return self;
}

- (void)dealloc
{
  [self unregisterAudioInterruptionNotifications];
  [audioPlayer setDelegate:nil];
}


#pragma mark - Pubic API


RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(play)
{
  if (!audioPlayer) {
    return;
  }
  if (audioPlayer.state == STKAudioPlayerStatePaused) {
    [audioPlayer resume];
  } else {
    [audioPlayer play:LPN_AUDIO_STREAM_URL];
  }

}

RCT_EXPORT_METHOD(pause)
{
  if (!audioPlayer) {
    return;
  } else {
    [audioPlayer pause];
  }
}

RCT_EXPORT_METHOD(resume)
{
  if (!audioPlayer) {
    return;
  } else {
    [audioPlayer resume];
  }
}

RCT_EXPORT_METHOD(stop)
{
  if (!audioPlayer) {
    return;
  } else {
    [audioPlayer stop];
  }
}

RCT_EXPORT_METHOD(getStatus: (RCTResponseSenderBlock) callback)
{
  if (!audioPlayer) {
    callback(@[[NSNull null], @{@"status": @"ERROR"}]);
  } else if ([audioPlayer state] == STKAudioPlayerStatePlaying) {
    callback(@[[NSNull null], @{@"status": @"PLAYING"}]);
  } else if ([audioPlayer state] == STKAudioPlayerStateBuffering) {
    callback(@[[NSNull null], @{@"status": @"BUFFERING"}]);
  } else {
    callback(@[[NSNull null], @{@"status": @"STOPPED"}]);
  }
}


#pragma mark - StreamingKit Audio Player


- (void)audioPlayer:(STKAudioPlayer *)player didStartPlayingQueueItemId:(NSObject *)queueItemId
{
  NSLog(@"AudioPlayer is playing");
}

- (void)audioPlayer:(STKAudioPlayer *)player didFinishPlayingQueueItemId:(NSObject *)queueItemId withReason:(STKAudioPlayerStopReason)stopReason andProgress:(double)progress andDuration:(double)duration
{
  NSLog(@"AudioPlayer has stopped");
}

- (void)audioPlayer:(STKAudioPlayer *)player didFinishBufferingSourceWithQueueItemId:(NSObject *)queueItemId
{
  NSLog(@"AudioPlayer finished buffering");
}

- (void)audioPlayer:(STKAudioPlayer *)player unexpectedError:(STKAudioPlayerErrorCode)errorCode {
  NSLog(@"AudioPlayer unexpected Error with code %d", errorCode);
}

- (void)audioPlayer:(STKAudioPlayer *)player stateChanged:(STKAudioPlayerState)state previousState:(STKAudioPlayerState)previousState
{
  NSLog(@"AudioPlayer state has changed");
  switch (state) {
    case STKAudioPlayerStatePlaying:
      [self.bridge.eventDispatcher sendDeviceEventWithName:@"AudioBridgeEvent"
                                                      body:@{@"status": @"PLAYING"}];
      break;

    case STKAudioPlayerStatePaused:
      [self.bridge.eventDispatcher sendDeviceEventWithName:@"AudioBridgeEvent"
                                                      body:@{@"status": @"PAUSED"}];
      break;

    case STKAudioPlayerStateStopped:
      [self.bridge.eventDispatcher sendDeviceEventWithName:@"AudioBridgeEvent"
                                                      body:@{@"status": @"STOPPED"}];
      break;

    case STKAudioPlayerStateBuffering:
      [self.bridge.eventDispatcher sendDeviceEventWithName:@"AudioBridgeEvent"
                                                      body:@{@"status": @"BUFFERING"}];
      break;

    case STKAudioPlayerStateError:
      [self.bridge.eventDispatcher sendDeviceEventWithName:@"AudioBridgeEvent"
                                                      body:@{@"status": @"ERROR"}];
      break;

    default:
      break;
  }
}


#pragma mark - Audio Session Methods


- (void)setSharedAudioSessionCategory
{
  NSError *categoryError = nil;

  // Create shared session and set audio session category allowing background playback
  [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&categoryError];
  
  if (categoryError) {
    NSLog(@"Error setting category! %@", [categoryError description]);
  }
}

- (void)registerAudioInterruptionNotifications
{
  // Register for audio interrupt notifications
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(onAudioInterruption:)
                                               name:AVAudioSessionInterruptionNotification
                                             object:nil];
  // Register for route change notifications
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(onRouteChangeInterruption:)
                                               name:AVAudioSessionRouteChangeNotification
                                             object:nil];
}

- (void)unregisterAudioInterruptionNotifications
{
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAudioSessionRouteChangeNotification
                                                object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAudioSessionInterruptionNotification
                                                object:nil];
}

- (void)onAudioInterruption:(NSNotification *)notification
{
  // Get the user info dictionary
  NSDictionary *interruptionDict = notification.userInfo;

  // Get the AVAudioSessionInterruptionTypeKey enum from the dictionary
  NSInteger interuptionType = [[interruptionDict valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];

  // Decide what to do based on interruption type
  switch (interuptionType)
  {
    case AVAudioSessionInterruptionTypeBegan:
      NSLog(@"Audio Session Interruption case started.");
      [audioPlayer pause];
      break;

    case AVAudioSessionInterruptionTypeEnded:
      NSLog(@"Audio Session Interruption case ended.");
      isPlayingWithOthers = [[AVAudioSession sharedInstance] isOtherAudioPlaying];
      (isPlayingWithOthers) ? [audioPlayer stop] : [audioPlayer resume];
      break;

    default:
      NSLog(@"Audio Session Interruption Notification case default.");
      break;
  }
}

- (void)onRouteChangeInterruption:(NSNotification*)notification
{

  NSDictionary *interruptionDict = notification.userInfo;
  NSInteger routeChangeReason = [[interruptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];

  switch (routeChangeReason)
  {
    case AVAudioSessionRouteChangeReasonUnknown:
      NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonUnknown");
      break;

    case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
      // A user action (such as plugging in a headset) has made a preferred audio route available.
      NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonNewDeviceAvailable");
      break;

    case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
      // The previous audio output path is no longer available.
      [audioPlayer stop];
      break;

    case AVAudioSessionRouteChangeReasonCategoryChange:
      // The category of the session object changed. Also used when the session is first activated.
      NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonCategoryChange"); //AVAudioSessionRouteChangeReasonCategoryChange
      break;

    case AVAudioSessionRouteChangeReasonOverride:
      // The output route was overridden by the app.
      NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonOverride");
      break;

    case AVAudioSessionRouteChangeReasonWakeFromSleep:
      // The route changed when the device woke up from sleep.
      NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonWakeFromSleep");
      break;

    case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
      // The route changed because no suitable route is now available for the specified category.
      NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory");
      break;
  }
}

@end
