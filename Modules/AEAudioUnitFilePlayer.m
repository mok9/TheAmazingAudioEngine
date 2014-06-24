//
//  AEAudioUnitFilePlayer.m
//  TheAmazingAudioEngine
//
//  TheAmazingAudioEngine Created by Michael Tyson
//
//  AEAudioUnitFilePlayer module Created by Rob Rampley on 25/03/2012
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "AEAudioUnitFilePlayer.h"

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        int fourCC = CFSwapInt32HostToBig(result);
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&fourCC);
        return NO;
    }
    return YES;
}

@interface AEAudioUnitFilePlayer ()
{
	AUNode _node;
	AudioUnit _audioUnit;
	AUNode _converterNode;
	AudioUnit _converterUnit;
	AUGraph _audioGraph;
	AEAudioController* _audioControllerRef;

	AudioFileID _audioUnitFile;
	SInt32 _locatehead;
	SInt32 _playhead;
	UInt32 _lengthInFrames;
}

- (id)initWithAudioController:(AEAudioController*)audioController error:(NSError**)error;
- (void)loadurl:(NSURL*)url error:(NSError**)error;
- (void)completionCallSetup;
- (void)completionCallComplete;

@property (nonatomic, assign) BOOL channelIsPlaying;
@property (nonatomic, assign) BOOL channelIsMuted;

@end

@implementation AEAudioUnitFilePlayer
@synthesize url=_url, audioDescription=_audioDescription, completionBlock=_completionBlock;


//-----------------------------------------------------------------------------
+ (id)audioUnitFilePlayerWithController:(AEAudioController*)audioController error:(NSError**)error
{
	return [[AEAudioUnitFilePlayer alloc] initWithAudioController:audioController error:error];
}

//-----------------------------------------------------------------------------
-(void)dealloc {
    if ( _node ) {
        checkResult(AUGraphRemoveNode(_audioGraph, _node), "AUGraphRemoveNode");
    }
    if ( _converterNode ) {
        checkResult(AUGraphRemoveNode(_audioGraph, _converterNode), "AUGraphRemoveNode");
    }
    
    checkResult(AUGraphUpdate(_audioGraph, NULL), "AUGraphUpdate");

    if ( _audioUnitFile ) {
        AudioFileClose(_audioUnitFile);
    }

    _audioControllerRef = nil;
}

//-----------------------------------------------------------------------------
-(void)setUrl:(NSURL *)url
{
	[self loadurl:url error:nil];
}

//-----------------------------------------------------------------------------
-(BOOL) playing
{
	return self.channelIsPlaying;
}

-(void) setPlaying:(BOOL)isPlaying
{
	if(isPlaying)
	{
		if (!self.channelIsPlaying)
		{
			// cancel any previous detection of playback finish we may have had going on
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completionCallSetup) object:nil];

			// need to reset before creating the new start region
			AudioUnitReset(_audioUnit, kAudioUnitScope_Global, 0);
			[self setupPlayRegion];

			self.channelIsPlaying = YES;

			// if we located close to the end, we need to fire up our end detection manually,
			// as audioRegionCompletion proc may not get called if we push out the buffer initially
			// a few seconds before the end seems to be a safe, but not overly agressive value
			NSTimeInterval ct = [self currentTime];
			NSTimeInterval dt = [self duration];
			if((dt-ct) < 3.0f) {
				[self completionCallSetup];
			}
		}
	}
	else if (self.channelIsPlaying)
	{
		// cancel any previous detection of playback finish we may have had going on
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completionCallSetup) object:nil];

		// call currentTime to update _playhead
		[self currentTime];
		_locatehead = _playhead;
		self.channelIsPlaying = NO;
	}
}

//-----------------------------------------------------------------------------
-(NSTimeInterval) duration
{
	if(_audioDescription.mSampleRate > 1.0f) {
		return (double)_lengthInFrames / (double)_audioDescription.mSampleRate;
	}
	return 0.0f;
}

-(NSTimeInterval) currentTime
{
	if(self.playing)
	{
		OSStatus result;
		AudioTimeStamp curTime;
		memset (&curTime, 0, sizeof(curTime));
		UInt32 valsz = sizeof(curTime);

		checkResult(result=AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_CurrentPlayTime,
															 kAudioUnitScope_Global, 0, &curTime, &valsz),
															 "AudioUnitGetProperty - kAudioUnitProperty_CurrentPlayTime");
	
		_playhead = (SInt32)curTime.mSampleTime;
		_playhead += _locatehead;
	}

	if(_audioDescription.mSampleRate > 1.0f) {
		return (double)_playhead / (double)_audioDescription.mSampleRate;
	}

	return 0.0f;
}

-(void)setCurrentTime:(NSTimeInterval)currentTime
{
	if((currentTime >= 0.0f) && (currentTime < [self duration]))
	{
		if (self.channelIsPlaying)
		{
			// call our own setPlaying to get things in order
			[self setPlaying:NO];
			_locatehead = currentTime * _audioDescription.mSampleRate;
			_playhead = _locatehead;
			[self setPlaying:YES];
		}
		else
		{
			_locatehead = currentTime * _audioDescription.mSampleRate;
			_playhead = _locatehead;
		}
	}
}

//-----------------------------------------------------------------------------
- (id)initWithAudioController:(AEAudioController*)audioController error:(NSError**)error
{
	self = [super init];
	if(self)
	{
		_url = nil;
		_audioUnitFile = nil;
		_audioUnit = nil;
		_converterUnit = nil;
		_audioControllerRef = nil;

		_playhead = 0;
		_locatehead = 0;
		_lengthInFrames = 0;
		
		_completionBlock = nil;

		AudioComponentDescription aedesc = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple, kAudioUnitType_Generator, kAudioUnitSubType_AudioFilePlayer);

		// the following is lifted from the AEAudioUnitChannel class
		
		// Create the node, and the audio unit
		 _audioGraph = audioController.audioGraph;
		OSStatus result;
		 if ( !checkResult(result=AUGraphAddNode(_audioGraph, &aedesc, &_node), "AUGraphAddNode") ||
				!checkResult(result=AUGraphNodeInfo(_audioGraph, _node, NULL, &_audioUnit), "AUGraphNodeInfo") ) {
			  
			  if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:[NSDictionary dictionaryWithObject:@"Couldn't initialise audio unit" forKey:NSLocalizedDescriptionKey]];
			  return nil;
		 }
		 
		 // Try to set the output audio description
		 AudioStreamBasicDescription audioDescription = audioController.audioDescription;
		 result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, sizeof(AudioStreamBasicDescription));
		 if ( result == kAudioUnitErr_FormatNotSupported ) {
			  // The audio description isn't supported. Assign modified default audio description, and create an audio converter.
			  AudioStreamBasicDescription defaultAudioDescription;
			  UInt32 size = sizeof(defaultAudioDescription);
			  result = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &defaultAudioDescription, &size);
			  defaultAudioDescription.mSampleRate = audioDescription.mSampleRate;
			  AEAudioStreamBasicDescriptionSetChannelsPerFrame(&defaultAudioDescription, audioDescription.mChannelsPerFrame);
			  if ( !checkResult(result=AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &defaultAudioDescription, size), "AudioUnitSetProperty") ) {
					if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:[NSDictionary dictionaryWithObject:@"Incompatible audio format" forKey:NSLocalizedDescriptionKey]];
					return nil;
			  }
			  
			  AudioComponentDescription audioConverterDescription = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple, kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
			  
			  if ( !checkResult(result=AUGraphAddNode(_audioGraph, &audioConverterDescription, &_converterNode), "AUGraphAddNode") ||
					 !checkResult(result=AUGraphNodeInfo(_audioGraph, _converterNode, NULL, &_converterUnit), "AUGraphNodeInfo") ||
					 !checkResult(result=AUGraphConnectNodeInput(_audioGraph, _node, 0, _converterNode, 0), "AUGraphConnectNodeInput") ||
					 !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &defaultAudioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") ||
					 !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") ) {
					
					if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:[NSDictionary dictionaryWithObject:@"Couldn't setup converter audio unit" forKey:NSLocalizedDescriptionKey]];
					return nil;
			  }
		 }

		 // Attempt to set the max frames per slice
		 UInt32 maxFPS = 4096;
		 AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS));
		 
		 checkResult(AUGraphUpdate(_audioGraph, NULL), "AUGraphUpdate");
		 
		 checkResult(AudioUnitInitialize(_audioUnit), "AudioUnitInitialize");
		 
		 if ( _converterUnit ) {
			  checkResult(AudioUnitInitialize(_converterUnit), "AudioUnitInitialize");
			  AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS));
		 }

		 _audioControllerRef = audioController;
		 self.volume = 1.0;
		 self.pan = 0.0;
		 self.channelIsMuted = NO;
		 self.channelIsPlaying = NO;
	}

	return self;
}

//-----------------------------------------------------------------------------
- (void)loadurl:(NSURL*)url error:(NSError**)error
{
	OSStatus result;

	if ( _audioUnitFile ) {
		AudioFileClose(_audioUnitFile);
		_audioUnitFile = nil;
	}
	_url = nil;
	_playhead = 0L;
	_locatehead = 0L;
	_lengthInFrames = 0L;

	if(url)
	{
		checkResult(result=AudioFileOpenURL((CFURLRef)CFBridgingRetain(url), kAudioFileReadPermission, 0, &_audioUnitFile), "AudioFileOpenURL");
		if(noErr == result)
		{
			 // Set the file to play
			 checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &_audioUnitFile, sizeof(_audioUnitFile)),
							 "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFileIDs)");

			 // Determine file properties
			 UInt64 packetCount;
			UInt32 size = sizeof(packetCount);
			checkResult(AudioFileGetProperty(_audioUnitFile, kAudioFilePropertyAudioDataPacketCount, &size, &packetCount),
							 "AudioFileGetProperty(kAudioFilePropertyAudioDataPacketCount)");
			
			size = sizeof(_audioDescription);
			checkResult(AudioFileGetProperty(_audioUnitFile, kAudioFilePropertyDataFormat, &size, &_audioDescription),
							 "AudioFileGetProperty(kAudioFilePropertyDataFormat)");

			_lengthInFrames = (UInt32)(packetCount * _audioDescription.mFramesPerPacket);
			_url = url;

			[self setupPlayRegion];
		}
	}

}

//-----------------------------------------------------------------------------
- (void)completionCallSetup
{
	// NSlog(@"AEAudioUnitFilePlayer - completionCallSetup\n");

	// We get the completion call after a notification for the last buffer
	// and -not- when audio is finished playing, so we need to let this continue
	// until playback has fully been played out.
	
	// NOTE: the actual amount of time between this completion callback being fired
	// and audio played out is different on various devices and iOS versions.  The
	// solution here is to just watch and monitor the actual ending, this seems to work
	// okay on newer(iPhone5) and older(iPad1) devices, also tested on iOS5 and iOS6 thus far.

	// we will keep calling ourselves until we see the current time pass the frame length
	if(self.playing)
	{
		OSStatus result;
		AudioTimeStamp curTime;
		memset (&curTime, 0, sizeof(curTime));
		UInt32 valsz = sizeof(curTime);

		checkResult(result=AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_CurrentPlayTime,
															 kAudioUnitScope_Global, 0, &curTime, &valsz),
															 "AudioUnitGetProperty - kAudioUnitProperty_CurrentPlayTime");
	
		_playhead = (SInt32)curTime.mSampleTime;
		_playhead += _locatehead;

		if(_playhead >= _lengthInFrames) {
			[self completionCallComplete];
		}
		else {
			// don't be overly busy here, just get a reasonably near completion
			[self performSelector:@selector(completionCallSetup) withObject:nil afterDelay:0.2f];
		}
	}

}

//-----------------------------------------------------------------------------
- (void)completionCallComplete
{
	// NSlog(@"AEAudioUnitFilePlayer - completionCallComplete\n");

	// playback has completed and buffers have been audibly played out
	self.channelIsPlaying = NO;
	_playhead = 0L;
	_locatehead = 0L;

	if ( _completionBlock ) {
		_completionBlock();
	}
}

//-----------------------------------------------------------------------------
// AEAudioControllerMainThreadMessageHandler
static void completionCallHandler(AEAudioController *audioController, void *userInfo, int userInfoLength)
{
	// NSlog(@"AEAudioUnitFilePlayer - completionCallHandler\n");

	if((userInfo) && (userInfoLength >= sizeof(void*)))
	{
		AEAudioUnitFilePlayer* THIS;
		memcpy((void*)&THIS, userInfo, sizeof(void*));

		[THIS completionCallSetup];
	}
}

//-----------------------------------------------------------------------------
static void audioRegionCompletion(void *userData, ScheduledAudioFileRegion *fileRegion, OSStatus result)
{
	if(userData)
	{
		AEAudioUnitFilePlayer *THIS = (__bridge AEAudioUnitFilePlayer*)userData;

		// already stopped?
		if((THIS->_channelIsPlaying) && (THIS->_audioControllerRef))
		{
			// get out of this callback quickly, handle it on the main thread
			AEAudioControllerSendAsynchronousMessageToMainThread(	THIS->_audioControllerRef,
                                                          		completionCallHandler, &userData, sizeof(void*) );
		}
	}
}

//-----------------------------------------------------------------------------
- (OSStatus)setupPlayRegion
{
	OSStatus result = -1;

	if(_audioUnitFile)
	{
		if(_locatehead >= _lengthInFrames) {
			_locatehead = 0;
		}

		ScheduledAudioFileRegion region;
		memset (&region.mTimeStamp, 0, sizeof(region.mTimeStamp));
		region.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
		region.mTimeStamp.mSampleTime = 0;
		region.mCompletionProc = audioRegionCompletion;
		region.mCompletionProcUserData = (__bridge void *)(self);
		region.mAudioFile = _audioUnitFile;
		region.mLoopCount = 0;
		region.mStartFrame = _locatehead;
		region.mFramesToPlay = _lengthInFrames - _locatehead;

		checkResult(result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &region, sizeof(region)),
						 "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFileRegion)");
		
		// Prime the player by reading some frames from disk
		UInt32 defaultNumberOfFrames = 0;
		checkResult(result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduledFilePrime, kAudioUnitScope_Global, 0, &defaultNumberOfFrames, sizeof(defaultNumberOfFrames)),
						 "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFilePrime)");
		 
		 // Set the start time (now = -1)
		 AudioTimeStamp startTime;
		memset (&startTime, 0, sizeof(startTime));
		startTime.mFlags = kAudioTimeStampSampleTimeValid;
		startTime.mSampleTime = -1;
		checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime)),
					"AudioUnitSetProperty(kAudioUnitProperty_ScheduleStartTimeStamp)");
	}

	return result;
}

//-----------------------------------------------------------------------------
static OSStatus renderCallback(id                        channel,
                               AEAudioController        *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    AEAudioUnitFilePlayer *THIS = (AEAudioUnitFilePlayer*)channel;
    AudioUnitRenderActionFlags flags = 0;
    checkResult(AudioUnitRender(THIS->_converterUnit ? THIS->_converterUnit : THIS->_audioUnit, &flags, time, 0, frames, audio), "AudioUnitRender");
	 return noErr;
}

-(AEAudioControllerRenderCallback)renderCallback {
    return renderCallback;
}

@end
