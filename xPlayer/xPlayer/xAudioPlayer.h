//
//  xAudioPlayer.h
//  xPlayerDemo
//
//  Created by JSK on 2018/3/18.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum xAudioState {
    xAudioStateNone = 0,
    xAudioStateLoading = 1,
    xAudioStatePlaying = 2,
    xAudioStateStopped = 4,
    xAudioStateError = 5
} xAudioState;

@protocol xAudioPlayerDelegate

// 会在main线程触发
-(void)onStateChanged:(xAudioState)audioState;

@end

@interface xAudioPlayer : NSObject

// url可以是rtmp，hls(http)，mp3..., 或者本地文件路径
-(instancetype)initWithUrl:(NSString*)url;

// 可重入
-(void)play;

// 可重入，释放前不必调用
-(void)stop;

@property(nonatomic, copy, readonly) NSString *url;

@property(nonatomic, readonly) xAudioState state;

@property(nonatomic, copy, readonly) NSString *errorMsg;  //当state为xAudioStateError时，存储错误信息

@property(nonatomic, weak) id<xAudioPlayerDelegate> delegate;

@end
