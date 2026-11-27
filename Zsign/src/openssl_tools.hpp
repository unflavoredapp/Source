//
//  p12_password_check.hpp
//  feather
//
//  Created by HAHALOSAH on 8/6/24.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
bool p12_password_check(NSString *file, NSString *pass);
/// Parse a p12 with OpenSSL and return the leaf certificate DER. System
/// SecPKCS12Import cannot handle PBES2/AES-256 encrypted p12 (errSecDecode);
/// this is the fallback.
NSData * _Nullable p12_certificate_der(NSString * _Nonnull file, NSString * _Nonnull pass);
/// Reason for the most recent p12_certificate_der failure (OpenSSL error stack), for diagnostics.
const char * _Nonnull p12_last_error(void);
/// Same as p12_certificate_der, but parses directly from memory without writing a temp file.
NSData * _Nullable p12_certificate_der_data(const void * _Nonnull bytes, size_t length, NSString * _Nonnull pass);
void password_check_fix_WHAT_THE_FUCK(NSString *path);
void password_check_fix_WHAT_THE_FUCK_free(NSString *path);
#ifdef __cplusplus
}
#endif
