//
//  DemoViewController.m
//  PLPlayerDemo
//
//  Created by JSK on 2018/3/26.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import "DemoViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <IJKMediaFramework/IJKMediaFramework.h>


@interface DemoViewController(){
    UITextField     *textfield;
    UITextView      *textView;
}
@property(nonatomic) IJKFFMoviePlayerController  *player;
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
            [self appendLog:[NSString stringWithFormat:@"AVAudioSession.setCategory() failed: %@\n", error ? [error localizedDescription] : @"nil"]];
        }
    }
    // Audio Interruptions
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:session];
    // IJKPlayer notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadStateDidChange:) name:IJKMPMoviePlayerLoadStateDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayBackDidFinish:) name:IJKMPMoviePlayerPlaybackDidFinishNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaIsPreparedToPlayDidChange:) name:IJKMPMediaPlaybackIsPreparedToPlayDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayBackStateDidChange:) name:IJKMPMoviePlayerPlaybackStateDidChangeNotification object:nil];
    return self;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IJKPlayer Demo";
    self.view.backgroundColor = [UIColor whiteColor];
    
    textfield = [[UITextField alloc] initWithFrame:CGRectMake(15, 100, [UIScreen mainScreen].bounds.size.width - 30, 40)];
    textfield.layer.borderWidth = 0.5;
    textfield.layer.borderColor = UIColor.blackColor.CGColor;
    textfield.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:textfield];
    
    [self addBtn:CGRectMake(50, 160, 120, 50) title:@"Start" selector:@selector(actionStart)];
    [self addBtn:CGRectMake(190, 160, 120, 50) title:@"Stop" selector:@selector(actionStop)];
    
    textView = [[UITextView alloc] initWithFrame:CGRectMake(15, 300, [UIScreen mainScreen].bounds.size.width - 30, 300)];
    textView.layer.borderWidth = 0.5;
    textView.layer.borderColor = UIColor.blackColor.CGColor;
    textView.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:textView];
    
    NSString *url;
//    url = @"rtmp://live.hkstv.hk.lxdns.com/live/hks"; //香港卫视
    url = @"http://ls.qingting.fm/live/386/64k.m3u8";
//    url = [[NSBundle mainBundle] pathForResource:@"sintel.mp4" ofType:nil];  //本地文件
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

- (void)actionStart{
    if([self activeSession]){
#ifdef DEBUG
        [IJKFFMoviePlayerController setLogReport:YES];
        [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_DEBUG];
#else
        [IJKFFMoviePlayerController setLogReport:NO];
        [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_INFO];
#endif
        [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
        IJKFFOptions *options = [IJKFFOptions optionsByDefault];
        NSURL *url = [NSURL URLWithString:textfield.text];
        _player = [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
        _player.shouldAutoplay = YES;
        [_player prepareToPlay];
    }
}

-(void)actionStop{
    [_player stop];
}

-(void)handleInterruption:(NSNotification*)notification{
    NSDictionary *info = notification.userInfo;
    int type = [info[AVAudioSessionInterruptionTypeKey] intValue];
    if(type == AVAudioSessionInterruptionTypeBegan){
        [_player stop];
    }
    else if(type == AVAudioSessionInterruptionTypeEnded){
        [_player play];
    }
}

-(BOOL)activeSession{
    NSError *error = nil;
    if(![[AVAudioSession sharedInstance] setActive:YES error:&error]){
        [self appendLog:[NSString stringWithFormat:@"AVAudioSession.setActive() failed: %@\n", error ? [error localizedDescription] : @"nil"]];
        return NO;
    }
    return YES;
}

-(void)appendLog:(NSString*)log{
    textView.text = [[textView.text stringByAppendingString:log] stringByAppendingString:@"\n"];
}

- (void)loadStateDidChange:(NSNotification*)notification
{
    //    MPMovieLoadStateUnknown        = 0,
    //    MPMovieLoadStatePlayable       = 1 << 0,
    //    MPMovieLoadStatePlaythroughOK  = 1 << 1, // Playback will be automatically started in this state when shouldAutoplay is YES
    //    MPMovieLoadStateStalled        = 1 << 2, // Playback will be automatically paused in this state, if started
    
    IJKMPMovieLoadState loadState = _player.loadState;
    
    if ((loadState & IJKMPMovieLoadStatePlaythroughOK) != 0) {
        [self appendLog:[NSString stringWithFormat:@"loadStateDidChange: IJKMPMovieLoadStatePlaythroughOK: %d\n", (int)loadState]];
    } else if ((loadState & IJKMPMovieLoadStateStalled) != 0) {
        [self appendLog:[NSString stringWithFormat:@"loadStateDidChange: IJKMPMovieLoadStateStalled: %d\n", (int)loadState]];
    } else {
        [self appendLog:[NSString stringWithFormat:@"loadStateDidChange: ???: %d\n", (int)loadState]];
    }
}

- (void)moviePlayBackDidFinish:(NSNotification*)notification
{
    //    MPMovieFinishReasonPlaybackEnded,
    //    MPMovieFinishReasonPlaybackError,
    //    MPMovieFinishReasonUserExited
    int reason = [[[notification userInfo] valueForKey:IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] intValue];
    
    switch (reason)
    {
        case IJKMPMovieFinishReasonPlaybackEnded:
            [self appendLog:[NSString stringWithFormat:@"playbackStateDidChange: IJKMPMovieFinishReasonPlaybackEnded: %d\n", reason]];
            break;
            
        case IJKMPMovieFinishReasonUserExited:
            [self appendLog:[NSString stringWithFormat:@"playbackStateDidChange: IJKMPMovieFinishReasonUserExited: %d\n", reason]];
            break;
            
        case IJKMPMovieFinishReasonPlaybackError:
            [self appendLog:[NSString stringWithFormat:@"playbackStateDidChange: IJKMPMovieFinishReasonPlaybackError: %d\n", reason]];
            break;
            
        default:
            [self appendLog:[NSString stringWithFormat:@"playbackPlayBackDidFinish: ???: %d\n", reason]];
            break;
    }
}

- (void)mediaIsPreparedToPlayDidChange:(NSNotification*)notification
{
    NSLog(@"mediaIsPreparedToPlayDidChange\n");
}

- (void)moviePlayBackStateDidChange:(NSNotification*)notification
{
    //    MPMoviePlaybackStateStopped,
    //    MPMoviePlaybackStatePlaying,
    //    MPMoviePlaybackStatePaused,
    //    MPMoviePlaybackStateInterrupted,
    //    MPMoviePlaybackStateSeekingForward,
    //    MPMoviePlaybackStateSeekingBackward
    
    switch (_player.playbackState)
    {
        case IJKMPMoviePlaybackStateStopped: {
            [self appendLog:[NSString stringWithFormat:@"IJKMPMoviePlayBackStateDidChange %d: stoped", (int)_player.playbackState]];
            break;
        }
        case IJKMPMoviePlaybackStatePlaying: {
            [self appendLog:[NSString stringWithFormat:@"IJKMPMoviePlayBackStateDidChange %d: playing", (int)_player.playbackState]];
            break;
        }
        case IJKMPMoviePlaybackStatePaused: {
            [self appendLog:[NSString stringWithFormat:@"IJKMPMoviePlayBackStateDidChange %d: paused", (int)_player.playbackState]];
            break;
        }
        case IJKMPMoviePlaybackStateInterrupted: {
            [self appendLog:[NSString stringWithFormat:@"IJKMPMoviePlayBackStateDidChange %d: interrupted", (int)_player.playbackState]];
            break;
        }
        case IJKMPMoviePlaybackStateSeekingForward:
        case IJKMPMoviePlaybackStateSeekingBackward: {
            [self appendLog:[NSString stringWithFormat:@"IJKMPMoviePlayBackStateDidChange %d: seeking", (int)_player.playbackState]];
            break;
        }
        default: {
            [self appendLog:[NSString stringWithFormat:@"IJKMPMoviePlayBackStateDidChange %d: unknown", (int)_player.playbackState]];
            break;
        }
    }
}

@end
