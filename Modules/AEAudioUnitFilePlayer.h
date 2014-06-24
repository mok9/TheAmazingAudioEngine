//
//  AEAudioUnitFilePlayer.h
//  TheAmazingAudioEngine
//
//  TheAmazingAudioEngine Created by Michael Tyson
//
//  AEAudioUnitFilePlayer module Created by Rob Rampley on 25/03/2012.
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

#import <Foundation/Foundation.h>
#import "TheAmazingAudioEngine.h"

/*!
 * Audio Unit File Player
 *
 *  This class makes use of the kAudioUnitSubType_AudioFilePlayer and is
 *  appropriate for larger files (eg. song files)
 *
 *  Transport (start/stop/locate) can be easily implemented using
 *  the 'playing' and 'currentTime' properties
 *
 *  This was originally intended as an alternative to AEAudioFilePlayer,
 *  for larger files where it is more efficient to use buffer streaming,
 *  rather than fully loading file contents into memory
 */
@interface AEAudioUnitFilePlayer : NSObject <AEAudioPlayable>

+ (id)audioUnitFilePlayerWithController:(AEAudioController*)audioController error:(NSError**)error;

@property (nonatomic, retain, readwrite) NSURL *url;        //!< media file URL (get or set)
@property (nonatomic, assign) BOOL playing;                 //!< set start-stop file playback, get playing state
@property (nonatomic, assign) NSTimeInterval currentTime;   //!< Current playback position, in seconds
@property (nonatomic, readonly) NSTimeInterval duration;    //!< Length of audio, in seconds
@property (nonatomic, assign) float volume;                 //!< Track volume
@property (nonatomic, assign) float pan;                    //!< Track pan
@property (nonatomic, readonly) AudioStreamBasicDescription audioDescription;  //!< Track audio description
@property (nonatomic, copy) void(^completionBlock)();       //!< A block to be called when playback finishes

@end
