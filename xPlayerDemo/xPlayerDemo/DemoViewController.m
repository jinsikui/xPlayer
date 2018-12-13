//
//  DemoViewController.m
//  xPlayerDemo
//
//  Created by JSK on 2018/3/20.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import "DemoViewController.h"
#import <xPlayer/xPlayer.h>
#import <AVFoundation/AVFoundation.h>


@interface DemoViewController()<xAudioPlayerDelegate>{
    UITextField     *textfield;
    xAudioPlayer    *audioPlayer;
    UITextView      *textView;
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
    //播放器会自动释放，无需调用[audioPlayer stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"xPlayer Demo";
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
    url = @"rtmp://live.hkstv.hk.lxdns.com/live/hks"; //香港卫视
//    url = @"http://ls.qingting.fm/live/386/64k.m3u8";
//    url = [[NSBundle mainBundle] pathForResource:@"sintel.mp4" ofType:nil];  //本地文件
//    url = @"rtmp://pili-live-rtmp.zhibo.qingting.fm/qingting-zhibo/prod_100027170_9d39e370-b7c0-11e7-88f5-55c2becd892e"; //夜将军正式环境
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
        audioPlayer = [[xAudioPlayer alloc] initWithUrl:textfield.text];
        audioPlayer.delegate = self;
        [audioPlayer play];
    }
}

-(void)actionStop{
    [audioPlayer stop];
}

-(void)handleInterruption:(NSNotification*)notification{
    NSDictionary *info = notification.userInfo;
    int type = [info[AVAudioSessionInterruptionTypeKey] intValue];
    if(type == AVAudioSessionInterruptionTypeBegan){
        [audioPlayer stop];
    }
    else if(type == AVAudioSessionInterruptionTypeEnded){
        if([self activeSession]){
            [audioPlayer play];
        }
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

#pragma mark - xAudioPlayerDelegate

-(void)onStateChanged:(xAudioState)audioState{
    NSString *str;
    switch (audioState) {
        case xAudioStateNone:
            str = @"None\n";
            break;
        case xAudioStateLoading:
            str = @"Loading\n";
            break;
        case xAudioStatePlaying:
            str = @"Playing\n";
            break;
        case xAudioStateStopped:
            str = @"Stopped\n";
            break;
        case xAudioStateError:
            str = [NSString stringWithFormat: @"Error: %@\n", audioPlayer.errorMsg];
        default:
            break;
    }
    textView.text = [textView.text stringByAppendingString:str];
}

@end
