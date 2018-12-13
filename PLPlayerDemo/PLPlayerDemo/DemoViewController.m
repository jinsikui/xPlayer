//
//  DemoViewController.m
//  PLPlayerDemo
//
//  Created by JSK on 2018/3/26.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import "DemoViewController.h"
#import "PLPlayerKit.h"
#import <AVFoundation/AVFoundation.h>


@interface DemoViewController()<PLPlayerDelegate>{
    UITextField     *textfield;
    UITextView      *textView;
    PLPlayer        *player;
}
@end

@implementation DemoViewController

-(instancetype)init{
    self = [super init];
    if(!self)
        return nil;
    
    // Audio Session
    NSError *error;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if(![session.category isEqualToString:AVAudioSessionCategoryPlayback] &&
       ![session.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]){
        if(![session setCategory:AVAudioSessionCategoryPlayback error:&error]){
            NSLog(@"AVAudioSession.setCategory() failed: %@\n", error ? [error localizedDescription] : @"nil");
        }
    }
    // Audio Interruptions
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:session];
    
    return self;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PLPlayer Demo";
    self.view.backgroundColor = [UIColor whiteColor];
    
    textfield = [[UITextField alloc] initWithFrame:CGRectMake(15, 100, [UIScreen mainScreen].bounds.size.width - 30, 40)];
    textfield.layer.borderWidth = 0.5;
    textfield.layer.borderColor = UIColor.blackColor.CGColor;
    textfield.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:textfield];
    
    [self addBtn:CGRectMake(50, 160, 120, 50) title:@"Start" selector:@selector(actionStart)];
    [self addBtn:CGRectMake(190, 160, 120, 50) title:@"Stop" selector:@selector(actionStop)];
    [self addBtn:CGRectMake(50, 230, 120, 50) title:@"next page" selector:@selector(actionNextPage)];
    
    textView = [[UITextView alloc] initWithFrame:CGRectMake(15, 300, [UIScreen mainScreen].bounds.size.width - 30, 300)];
    textView.layer.borderWidth = 0.5;
    textView.layer.borderColor = UIColor.blackColor.CGColor;
    textView.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:textView];
    
    NSString *url;
//    url = @"rtmp://live.hkstv.hk.lxdns.com/live/hks"; //香港卫视
//    url = @"http://ls.qingting.fm/live/386/64k.m3u8";
    url = [[NSBundle mainBundle] pathForResource:@"sintel.mp4" ofType:nil];  //本地文件
//    url = @"rtmp://pili-live-rtmp.zhibo.qingting.fm/qingting-zhibo/prod_100027170_9d39e370-b7c0-11e7-88f5-55c2becd892e?only-audio=1"; //夜将军正式环境
//    url = @"http://pili-live-hls.zhibo.qingting.fm/qingting-zhibo/prod_100027170_9d39e370-b7c0-11e7-88f5-55c2becd892e.m3u8"; //夜将军正式hls
//    url = @"rtmp://pili-publish.partner.zhibo.qingting.fm/qingting-zhibo-partner/test_agora4";
    textfield.text = url;
}

- (void)addBtn:(CGRect)frame title:(NSString*)title selector:(SEL)selector{
    UIButton *btn = [[UIButton alloc] initWithFrame:frame];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blueColor] forState: UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    btn.layer.borderColor = [UIColor blueColor].CGColor;
    btn.layer.borderWidth = 0.5;
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
}

-(void)actionNextPage{
    [self.navigationController pushViewController:[[DemoViewController alloc] init] animated:YES];
}

- (void)actionStart{
    if([self activeSession]){
        PLPlayerOption *option = [PLPlayerOption defaultOption];
        [option setOptionValue:@15 forKey:PLPlayerOptionKeyTimeoutIntervalForMediaPackets];
        NSURL *url = [NSURL URLWithString:textfield.text];
        player = [PLPlayer playerWithURL:url option:option];
        player.delegate = self;
        [player play];
    }
}

-(void)actionStop{
    [player stop];
}

-(void)handleInterruption:(NSNotification*)notification{
    NSDictionary *info = notification.userInfo;
    int type = [info[AVAudioSessionInterruptionTypeKey] intValue];
    if(type == AVAudioSessionInterruptionTypeBegan){
        [player stop];
    }
    else if(type == AVAudioSessionInterruptionTypeEnded){
        [player play];
    }
}

-(BOOL)activeSession{
    NSError *error = nil;
    if(![[AVAudioSession sharedInstance] setActive:YES error:&error]){
        NSLog(@"AVAudioSession.setActive() failed: %@\n", error ? [error localizedDescription] : @"nil");
        return NO;
    }
    return YES;
}

#pragma mark - PLPlayerDelegate

/**
 告知代理对象播放器状态变更
 
 @param player 调用该方法的 PLPlayer 对象
 @param state  变更之后的 PLPlayer 状态
 
 @since v1.0.0
 */
- (void)player:(nonnull PLPlayer *)player statusDidChange:(PLPlayerStatus)state{
    NSString *strState;
    switch (state) {
        /**
         PLPlayer 未知状态，只会作为 init 后的初始状态，开始播放之后任何情况下都不会再回到此状态。
         @since v1.0.0
         */
        case PLPlayerStatusUnknow:
            strState = @"Unknow";
            break;
        
        /**
         PLPlayer 正在准备播放所需组件，在调用 -play 方法时出现。
         
         @since v1.0.0
         */
        case PLPlayerStatusPreparing:
            strState = @"Preparing";
            break;
        
        /**
         PLPlayer 播放组件准备完成，准备开始播放，在调用 -play 方法时出现。
         
         @since v1.0.0
         */
        case PLPlayerStatusReady:
            strState = @"Ready";
            break;
        
        /**
         @abstract PLPlayer 缓存数据为空状态。
         
         @discussion 特别需要注意的是当推流端停止推流之后，PLPlayer 将出现 caching 状态直到 timeout 后抛出 timeout 的 error 而不是出现 PLPlayerStatusStopped 状态，因此在直播场景中，当流停止之后一般做法是使用 IM 服务告知播放器停止播放，以达到即时响应主播断流的目的。
         
         @since v1.0.0
         */
        case PLPlayerStatusCaching:
            strState = @"Caching";
            break;
        
        /**
         PLPlayer 正在播放状态。
         
         @since v1.0.0
         */
        case PLPlayerStatusPlaying:
            strState = @"Playing";
            break;
        
        /**
         PLPlayer 暂停状态。
         
         @since v1.0.0
         */
        case PLPlayerStatusPaused:
            strState = @"Paused";
            break;
        
        /**
         @abstract PLPlayer 停止状态
         @discussion 该状态仅会在回放时播放结束出现，RTMP 直播结束并不会出现此状态
         
         @since v1.0.0
         */
        case PLPlayerStatusStopped:
            strState = @"Stopped";
            break;
        
        /**
         PLPlayer 错误状态，播放出现错误时会出现此状态。
         
         @since v1.0.0
         */
        case PLPlayerStatusError:
            strState = @"Error";
            break;
        
        /**
         *  PLPlayer 自动重连的状态
         */
        case PLPlayerStateAutoReconnecting:
            strState = @"AutoReconnecting";
            break;
        
        /**
         *  PLPlayer 播放完成（该状态只针对点播有效）
         */
        case PLPlayerStatusCompleted:
            strState = @"Completed";
            break;
    }
    textView.text = [textView.text stringByAppendingFormat:@"%@\n", strState];
}

/**
 告知代理对象播放器因错误停止播放
 
 @param player 调用该方法的 PLPlayer 对象
 @param error  携带播放器停止播放错误信息的 NSError 对象
 
 @since v1.0.0
 */
- (void)player:(nonnull PLPlayer *)player stoppedWithError:(nullable NSError *)error{
    textView.text = [textView.text stringByAppendingFormat:@"stoppedWithError: %@\n", error];
}

@end
