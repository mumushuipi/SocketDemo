//
//  ViewController.m
//  TCPScoketClient
//
//  Created by 林波 on 2018/6/27.
//  Copyright © 2018年 林波. All rights reserved.
//

#import "ViewController.h"
#import <CocoaAsyncSocket/GCDAsyncSocket.h>
#import <sys/errno.h>

// 定义包头
typedef struct tagNetPacketHead
{
    int version;                      //版本
    int eMainType;                  //包类型主协议
    int eSubType;                    //包类型子协议
    unsigned int nLen;              //包体长度
} NetPacketHead;

// 定义发包类型
typedef struct tagNetPacket
{
    NetPacketHead netPacketHead;      //包头
    unsigned char *packetBody;      //包体
} NetPacket;


@interface ViewController ()<GCDAsyncSocketDelegate>
@property (weak, nonatomic) IBOutlet UITextField *hostTextField;
@property (weak, nonatomic) IBOutlet UITextField *portTextField;
@property (weak, nonatomic) IBOutlet UITextView *messageTextView;
@property (weak, nonatomic) IBOutlet UITextField *inputTextField;
@property (nonatomic, strong) GCDAsyncSocket *clientSocket;
@property (nonatomic, strong) NSTimer *heartTimer;// 心跳计时器
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
}
- (IBAction)actioConnect:(UIButton *)sender {
    if ([sender.currentTitle isEqualToString:@"连接"]) {
        [sender setTitle:@"断开连接" forState:UIControlStateNormal];
        NSError *error;
        BOOL isConnect = [self.clientSocket connectToHost:self.hostTextField.text onPort:[self.portTextField.text intValue] error:&error];
        if (isConnect) {
            [self addMessage:@"连接成功"];
        }else{
            [self addMessage:@"连接失败"];
        }
        [self.clientSocket readDataWithTimeout:-1 tag:0];
    }else{
        [sender setTitle:@"连接" forState:UIControlStateNormal];
        [self.clientSocket disconnect];
//        self.clientSocket.userData = @(SocketOfflineByUser);
    }
}

- (IBAction)actionSend:(id)sender {
    [self.view endEditing:YES];
    if (self.inputTextField.text.length <= 0) return;
    NSData *data = [self.inputTextField.text dataUsingEncoding:NSUTF8StringEncoding];
    [self.clientSocket writeData:data withTimeout:-1 tag:0];
}

- (void)actionLongConnect{
//    根据服务器要求发送固定格式的数据，假设为指令@"longConnect"，但是一般不会是这么简单的指令
    NSString *longConnect = @"longConnect";
    NSData   *dataStream  = [longConnect dataUsingEncoding:NSUTF8StringEncoding];// utf8编码的中文一般是3个字节，所以data.length = 3
    [self.clientSocket writeData:dataStream withTimeout:1 tag:1];
}

-(void)addMessage:(NSString *)str{
    self.messageTextView.text = [self.messageTextView.text stringByAppendingFormat:@"%@\n\n\n",str];
    [self.messageTextView scrollRangeToVisible:[self.messageTextView.text rangeOfString:str options:NSBackwardsSearch]];
}

#pragma mark - GCDAsyncSocketDelegate
-(void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag{
    [self addMessage:@"写入完成"];
    [self.clientSocket readDataWithTimeout:-1 tag:tag];
}

-(void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port{
    [self addMessage:[NSString stringWithFormat:@"连接上%@\nlocal:%@",host,sock]];
    [self.clientSocket readDataWithTimeout:-1 tag:0];
    if (!_heartTimer) {
        _heartTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(actionLongConnect) userInfo:nil repeats:YES];;
    }
}

-(void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err{
    if (err) {
        if (err.code == 57) {// 错误码请见 sys/errno.h
//            sock.userData = @(SocketOfflineByWifiCut);// wifi断开
        }else{
//            sock.userData = @(SocketOfflineByServer);// 服务器掉线
        }
        [self addMessage:[NSString stringWithFormat:@"断开连接，出错了%@\n",err]];
    }else{
        [self addMessage:[NSString stringWithFormat:@"断开连接"]];
    }
    if (_heartTimer) {
        [_heartTimer invalidate];
        _heartTimer = nil;
    }
}

-(void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag{
    NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self addMessage:[NSString stringWithFormat:@"读到的数据：%@ \nhost:%@", dataString, sock.connectedHost]];
    [sock readDataWithTimeout:-1 tag:0];
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self.view endEditing:YES];
}

- (void)disposeBufferData:(NSData *)data {
    @synchronized (@"") {
        NSMutableData *_bufferData = [[NSMutableData alloc] init];
        [_bufferData appendData:data];
        while (_bufferData.length >= 16) {
            struct tagNetPacketHead head;
            
            [_bufferData getBytes:&head range:NSMakeRange(0, 16)];
            while (_bufferData.length >= 16 && !(head.version == 1 && head.eMainType > -10 && head.eMainType < 1000 && head.eSubType > - 10 && head.eSubType < 1000)) {
                int a = (int)_bufferData.length - 1;
                _bufferData = [_bufferData subdataWithRange:NSMakeRange(1, a)].mutableCopy;
                if (_bufferData.length >= 16) {
                    [_bufferData getBytes:&head range:NSMakeRange(0, 16)];
                }
            }
            
            BOOL isIn = !(head.nLen > (_bufferData.length - 16));
            if (isIn && _bufferData.length >= 16) {
                NSMutableData *pendingData = [NSMutableData data];
                if (head.eSubType == -1) {
                    pendingData = [_bufferData subdataWithRange:NSMakeRange(4, 4)].mutableCopy;
                    [pendingData appendData:[_bufferData subdataWithRange:NSMakeRange(16, head.nLen)]];
                }
                else {
                    pendingData = [_bufferData subdataWithRange:NSMakeRange(4, 8)].mutableCopy;
                    NSLog(@"%d", head.nLen);
                    [pendingData appendData:[_bufferData subdataWithRange:NSMakeRange(16, head.nLen)]];
                }
                
//                [DisposeManager disposeData:pendingData num:head.eMainType];
                int totalLen = _bufferData.length;
                _bufferData = [_bufferData subdataWithRange:NSMakeRange(16 + head.nLen, totalLen - 16 - head.nLen)].mutableCopy;
            }
        }
    }
}

@end
