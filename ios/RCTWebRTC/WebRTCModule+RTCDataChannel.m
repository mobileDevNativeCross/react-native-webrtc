#import <objc/runtime.h>

#import "RCTBridge.h"
#import "RCTEventDispatcher.h"

#import "WebRTCModule+RTCDataChannel.h"

@implementation WebRTCModule (RTCDataChannel)

RCT_EXPORT_METHOD(createDataChannel:(nonnull NSNumber *)peerConnectionId
                              label:(NSString *)label
                             config:(RTCDataChannelInit *)config
{
  RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
  RTCDataChannel *dataChannel = [peerConnection createDataChannelWithLabel:label config:config];
  NSInteger dataChannelId = dataChannel.streamId;
  // XXX RTP data channels are not defined by the WebRTC standard, have been
  // deprecated in Chromium, and Google have decided (in 2015) to no longer
  // support them (in the face of multiple reported issues of breakages).
  if (-1 != dataChannelId) {
    self.dataChannels[@(dataChannelId)] = dataChannel;
    dataChannel.delegate = self;
  }
})

RCT_EXPORT_METHOD(dataChannelSend:(nonnull NSNumber *)dataChannelId
                             data:(NSString *)data
                             type:(NSString *)type
{
  RTCDataChannel *dataChannel = self.dataChannels[dataChannelId];
  NSData *bytes = [type isEqualToString:@"binary"] ?
    [[NSData alloc] initWithBase64EncodedString:data options:0] :
    [data dataUsingEncoding:NSUTF8StringEncoding];
  RTCDataBuffer *buffer = [[RTCDataBuffer alloc] initWithData:bytes isBinary:[type isEqualToString:@"binary"]];
  [dataChannel sendData:buffer];
})

RCT_EXPORT_METHOD(dataChannelClose:(nonnull NSNumber *)dataChannelId
{
  RTCDataChannel *dataChannel = self.dataChannels[dataChannelId];
  [dataChannel close];
  [self.dataChannels removeObjectForKey:dataChannelId];
})

- (NSString *)stringForDataChannelState:(RTCDataChannelState)state
{
  switch (state) {
    case kRTCDataChannelStateConnecting: return @"connecting";
    case kRTCDataChannelStateOpen: return @"open";
    case kRTCDataChannelStateClosing: return @"closing";
    case kRTCDataChannelStateClosed: return @"closed";
  }
  return nil;
}

#pragma mark - RTCDataChannelDelegate methods

// Called when the data channel state has changed.
- (void)channelDidChangeState:(RTCDataChannel*)channel
{
  NSDictionary *event = @{@"id": @(channel.streamId),
                          @"state": [self stringForDataChannelState:channel.state]};
  [self.bridge.eventDispatcher sendDeviceEventWithName:@"dataChannelStateChanged"
                                                  body:event];
}

// Called when a data buffer was successfully received.
- (void)channel:(RTCDataChannel*)channel didReceiveMessageWithBuffer:(RTCDataBuffer*)buffer
{
  NSString *type;
  NSString *data;
  if (buffer.isBinary) {
    type = @"binary";
    data = [buffer.data base64EncodedStringWithOptions:0];
  } else {
    type = @"text";
    // XXX NSData has a length property which means that, when it represents
    // text, the value of its bytes property does not have to be terminated by
    // null. In such a case, NSString's stringFromUTF8String may fail and return
    // nil (which would crash the process when inserting data into NSDictionary
    // without the nil protection implemented below).
    data = [[NSString alloc] initWithData:buffer.data
                                 encoding:NSUTF8StringEncoding];
  }
  NSDictionary *event = @{@"id": @(channel.streamId),
                          @"type": type,
                          // XXX NSDictionary will crash the process upon
                          // attempting to insert nil. Such behavior is
                          // unacceptable given that protection in such a
                          // scenario is extremely simple.
                          @"data": (data ? data : [NSNull null])};
  [self.bridge.eventDispatcher sendDeviceEventWithName:@"dataChannelReceiveMessage"
                                                  body:event];
}

@end
