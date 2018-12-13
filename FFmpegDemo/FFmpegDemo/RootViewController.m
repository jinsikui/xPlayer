//
//  RootViewController.m
//  FFmpegDemo
//
//  Created by JSK on 2018/2/22.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import "RootViewController.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavfilter/avfilter.h>

@interface RootViewController ()

@end

@implementation RootViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    self.title = @"FFmpeg Demo";
    self.view.backgroundColor = [UIColor whiteColor];
    
    av_register_all();
    
    //configuration
    printf("configuration\n");
    printf("%s\n", avcodec_configuration());
    
    //protocol
    printf("\nprotocol\n");
    struct URLProtocol *pup = NULL;
    //Input
    struct URLProtocol **p_temp = &pup;
    avio_enum_protocols((void **)p_temp, 0);
    while ((*p_temp) != NULL){
        printf("[In ][%10s]\n", avio_enum_protocols((void **)p_temp, 0));
    }
    pup = NULL;
    //Output
    avio_enum_protocols((void **)p_temp, 1);
    while ((*p_temp) != NULL){
        printf("[Out][%10s]\n", avio_enum_protocols((void **)p_temp, 1));
    }
    
    //format
    printf("\nformat\n");
    AVInputFormat *if_temp = av_iformat_next(NULL);
    AVOutputFormat *of_temp = av_oformat_next(NULL);
    //Input
    while(if_temp!=NULL){
        printf("[In ]%10s\n", if_temp->name);
        if_temp=if_temp->next;
    }
    //Output
    while (of_temp != NULL){
        printf("[Out]%10s\n", of_temp->name);
        of_temp = of_temp->next;
    }
    
    //codec
    printf("\ncodec\n");
    AVCodec *c_temp = av_codec_next(NULL);
    while(c_temp!=NULL){
        if (c_temp->decode!=NULL){
            printf("[Dec]");
        }
        else{
            printf("[Enc]");
        }
        switch (c_temp->type){
            case AVMEDIA_TYPE_VIDEO:
                printf("[Video]");
                break;
            case AVMEDIA_TYPE_AUDIO:
                printf("[Audio]");
                break;
            default:
                printf("[Other]");
                break;
        }
        printf("%10s\n", c_temp->name);
        c_temp=c_temp->next;
    }
    
    //filter
    printf("\nfilter\n");
    AVFilter *f_temp = (AVFilter *)avfilter_next(NULL);
    while (f_temp != NULL){
        printf("[%10s]\n", f_temp->name);
    }
}

@end
