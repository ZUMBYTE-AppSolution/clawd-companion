#import <Foundation/Foundation.h>
#import <SafariServices/SafariServices.h>

// Safari routes native messages exclusively to this extension's handler.
@interface ClawdSafariHandler : NSObject <NSExtensionRequestHandling, NSURLSessionTaskDelegate>
@end

@implementation ClawdSafariHandler
- (void)reply:(NSDictionary *)result to:(NSExtensionContext *)context {
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{SFExtensionMessageKey: result};
    [context completeRequestReturningItems:@[item] completionHandler:nil];
}

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    NSExtensionItem *item = context.inputItems.firstObject;
    NSDictionary *message = [item isKindOfClass:NSExtensionItem.class] ? item.userInfo[SFExtensionMessageKey] : nil;
    if (![message isKindOfClass:NSDictionary.class]) {
        [self reply:@{@"ok": @NO, @"reason": @"rejected"} to:context];
        return;
    }
    NSString *token = message[@"token"];
    id event = message[@"event"];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+/=.-"];
    if (![token isKindOfClass:NSString.class] || token.length < 8 || token.length > 256 ||
        [token rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound ||
        ![event isKindOfClass:NSDictionary.class] || ![NSJSONSerialization isValidJSONObject:event]) {
        [self reply:@{@"ok": @NO, @"reason": @"rejected"} to:context];
        return;
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    if (!body || body.length > 4096) {
        [self reply:@{@"ok": @NO, @"reason": @"rejected"} to:context];
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:49217/v1/events"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.timeoutInterval = 3;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.URLCache = nil;
    configuration.connectionProxyDictionary = @{};
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *reason = error ? @"offline" : ((code == 401 || code == 403) ? @"token" : @"rejected");
        BOOL ok = !error && code == 200;
        [self reply:(ok ? @{@"ok": @YES} : @{@"ok": @NO, @"reason": reason}) to:context];
        [session finishTasksAndInvalidate];
    }];
    [task resume];
}

// Keep the bearer token bound to the single loopback endpoint.
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil);
}
@end
