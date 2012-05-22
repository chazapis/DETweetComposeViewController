//
//  DETweetPoster.m
//  DETweeter
//
//  Copyright (c) 2011 Double Encore, Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer 
//  in the documentation and/or other materials provided with the distribution. Neither the name of the Double Encore Inc. nor the names of its 
//  contributors may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
//  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS 
//  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
//  GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
//  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "DETweetPoster.h"
#import "UIDevice+DETweetComposeViewController.h"
#import <Accounts/Accounts.h>
#import <Twitter/TWRequest.h>


@interface DETweetPoster ()

@property (nonatomic, retain) NSURLConnection *postConnection;

- (void)sendFailedToDelegate;
- (void)sendFailedAuthenticationToDelegate;
- (void)sendSuccessToDelegate;

@end


@implementation DETweetPoster

NSString * const twitterPostURLString = @"https://api.twitter.com/1/statuses/update.json";
NSString * const twitterPostWithImagesURLString = @"https://upload.twitter.com/1/statuses/update_with_media.json";
NSString * const twitterStatusKey = @"status";

@synthesize delegate = _delegate;
@synthesize postConnection = _postConnection;
@synthesize responseData = _responseData;


#pragma mark - Class Methods

+ (NSArray *)accounts
{
    if (![UIDevice de_isIOS5]) {
        return nil;
    }
    ACAccountStore *accountStore = [[[ACAccountStore alloc] init] autorelease];
    ACAccountType *twitterAccountType = [accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    NSArray *twitterAccounts = [accountStore accountsWithAccountType:twitterAccountType];
    return twitterAccounts;
}


#pragma mark - Setup & Teardown

- (void)dealloc
{
    _delegate = nil;
    [_postConnection cancel];
    [_postConnection release], _postConnection = nil;
    [_responseData release], _responseData = nil;
  
    [super dealloc];
}


#pragma mark - Public

- (void)postTweet:(NSString *)tweetText withImages:(NSArray *)images
    // Posts the tweet with the first available account on iOS 5.
{
    id account = nil;  // An ACAccount. But that didn't exist on iOS 4.
    if ([UIDevice de_isIOS5]) {
        NSArray *twitterAccounts = [[self class] accounts];
        if ([twitterAccounts count] > 0) {
            account = [twitterAccounts objectAtIndex:0];
            [self postTweet:tweetText withImages:images fromAccount:account];
        }
        else {
            [self sendFailedToDelegate];
        }
    }
}


- (void)postTweet:(NSString *)tweetText withImages:(NSArray *)images fromAccount:(id)account
{
    NSURLRequest *postRequest = nil;
    if ([UIDevice de_isIOS5] && account != nil) {        
        TWRequest *twRequest = nil;
        if ([images count] > 0) {
            twRequest = [[[TWRequest alloc] initWithURL:[NSURL URLWithString:twitterPostWithImagesURLString]
                                            parameters:nil requestMethod:TWRequestMethodPOST] autorelease];
            
            [images enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                UIImage *image = (UIImage *)obj;
                [twRequest addMultiPartData:UIImagePNGRepresentation(image) withName:@"media[]" type:@"multipart/form-data"];
            }];
            
            [twRequest addMultiPartData:[tweetText dataUsingEncoding:NSUTF8StringEncoding] 
                             withName:twitterStatusKey type:@"multipart/form-data"];
        }
        else {
            NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:tweetText, twitterStatusKey, nil];
            twRequest = [[[TWRequest alloc] initWithURL:[NSURL URLWithString:twitterPostURLString]
                                            parameters:parameters requestMethod:TWRequestMethodPOST] autorelease];
        }
            // There appears to be a bug in iOS 5.0 that gives us trouble if we used our retained account.
            // If we get it again using the identifier then everything works fine.
        ACAccountStore *accountStore = [[[ACAccountStore alloc] init] autorelease];
        twRequest.account = [accountStore accountWithIdentifier:((ACAccount *)account).identifier];
        postRequest = [twRequest signedURLRequest];
    }
    
    if ([NSURLConnection canHandleRequest:postRequest]) {
        self.postConnection = [NSURLConnection connectionWithRequest:postRequest delegate:self];
        [self.postConnection start];
        self.responseData = [NSMutableData data];
    }
    else {
        [self sendFailedToDelegate];
    }
}


#pragma mark - Private methods

- (void)sendFailedToDelegate
{
    if ([self.delegate respondsToSelector:@selector(tweetFailed:)]) {
        [self.delegate tweetFailed:self];
    }
}


- (void)sendFailedAuthenticationToDelegate
{
    if ([self.delegate respondsToSelector:@selector(tweetFailedAuthentication:)]) {
        [self.delegate tweetFailedAuthentication:self];
    }
}


- (void)sendSuccessToDelegate
{
    if ([self.delegate respondsToSelector:@selector(tweetSucceeded:)]) {
        [self.delegate tweetSucceeded:self];
    }
}


#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self sendFailedToDelegate];
    [_postConnection release];
    _postConnection = nil;
    [_responseData release];
    _responseData = nil;
}


#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response
{
    NSInteger statusCode = [response statusCode];
    
    NSRange successRange = NSMakeRange(200, 5);
    if (NSLocationInRange(statusCode, successRange)) {
        [self.responseData setLength:0];
        return;
    }
    else if (statusCode == 401) {
        // Failed authentication
        [self sendFailedAuthenticationToDelegate];
    }
    else {
        [self sendFailedToDelegate];
    }
    [_postConnection release];
    _postConnection = nil;
    [_responseData release];
    _responseData = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.responseData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self sendSuccessToDelegate];
    [_postConnection release];
    _postConnection = nil;
    [_responseData release];
    _responseData = nil;
}


@end
