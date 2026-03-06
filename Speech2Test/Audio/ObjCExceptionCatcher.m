#import "ObjCExceptionCatcher.h"

BOOL S2TCatchObjCException(void (NS_NOESCAPE ^block)(void),
                           NSError * _Nullable __autoreleasing * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.elicarter.Speech2Test.ObjCException"
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: exception.name,
                @"NSExceptionName": exception.name,
            }];
        }
        return NO;
    }
}
