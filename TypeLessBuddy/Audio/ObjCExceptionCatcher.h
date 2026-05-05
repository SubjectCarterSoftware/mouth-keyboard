#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes a block and catches any ObjC NSException, returning it as an NSError.
/// Returns YES on success, NO if an exception was caught (error is populated).
BOOL S2TCatchObjCException(void (NS_NOESCAPE ^block)(void),
                           NSError * _Nullable __autoreleasing * _Nullable error);

NS_ASSUME_NONNULL_END
