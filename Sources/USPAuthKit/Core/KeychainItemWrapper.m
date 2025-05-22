/*
     File: KeychainItemWrapper.m 
 Abstract: 
 Objective-C wrapper for accessing a single keychain item.
  
  Version: 1.2 
  
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple 
 Inc. ("Apple") in consideration of your agreement to the following 
 terms, and your use, installation, modification or redistribution of 
 this Apple software constitutes acceptance of these terms.  If you do 
 not agree with these terms, please do not use, install, modify or 
 redistribute this Apple software. 
  
 In consideration of your agreement to abide by the following terms, and 
 subject to these terms, Apple grants you a personal, non-exclusive 
 license, under Apple's copyrights in this original Apple software (the 
 "Apple Software"), to use, reproduce, modify and redistribute the Apple 
 Software, with or without modifications, in source and/or binary forms; 
 provided that if you redistribute the Apple Software in its entirety and 
 without modifications, you must retain this notice and the following 
 text and disclaimers in all such redistributions of the Apple Software. 
 Neither the name, trademarks, service marks or logos of Apple Inc. may 
 be used to endorse or promote products derived from the Apple Software 
 without specific prior written permission from Apple.  Except as 
 expressly stated in this notice, no other rights or licenses, express or 
 implied, are granted by Apple herein, including but not limited to any 
 patent rights that may be infringed by your derivative works or by other 
 works in which the Apple Software may be incorporated. 
  
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE 
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION 
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS 
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND 
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS. 
  
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL 
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, 
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED 
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), 
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE 
 POSSIBILITY OF SUCH DAMAGE. 
  
 Copyright (C) 2010 Apple Inc. All Rights Reserved. 
  
*/ 

// Sources/USPAuthKit/Core/KeychainItemWrapper.m

#import "KeychainItemWrapper.h"
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@interface KeychainItemWrapper ()

@property (nonatomic, strong) NSMutableDictionary *keychainItemData;
@property (nonatomic, strong) NSMutableDictionary *genericPasswordQuery;

// Métodos “privados” usados internamente:
- (void)resetKeychainItem;
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert;
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert;
- (void)writeToKeychain;

@end

@implementation KeychainItemWrapper

- (instancetype)initWithIdentifier:(NSString *)identifier
                      accessGroup:(nullable NSString *)accessGroup
{
    if (!(self = [super init])) return nil;
    
    // Prepara query genérica para buscar o item
    _genericPasswordQuery = [@{
        (__bridge id)kSecClass:           (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrGeneric:     identifier,
        (__bridge id)kSecMatchLimit:      (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecReturnAttributes:(__bridge id)kCFBooleanTrue
    } mutableCopy];
    
#if !TARGET_IPHONE_SIMULATOR
    if (accessGroup) {
        _genericPasswordQuery[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    }
#endif

    CFDictionaryRef outDict = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)_genericPasswordQuery,
                                          (CFTypeRef *)&outDict);
    if (status == errSecSuccess && outDict) {
        // Item existe, carregamos os atributos
        _keychainItemData = [self secItemFormatToDictionary:(__bridge NSDictionary *)outDict];
        CFRelease(outDict);
    } else {
        // Não existe ainda: criamos padrão
        [self resetKeychainItem];
        // adiciona generic identifier também no novo item
        _keychainItemData[(__bridge id)kSecAttrGeneric] = identifier;
#if !TARGET_IPHONE_SIMULATOR
        if (accessGroup) {
            _keychainItemData[(__bridge id)kSecAttrAccessGroup] = accessGroup;
        }
#endif
    }

    return self;
}

- (void)setObject:(id)inObject forKey:(id)key {
    if (!inObject) return;
    id current = self.keychainItemData[key];
    if (![current isEqual:inObject]) {
        self.keychainItemData[key] = inObject;
        [self writeToKeychain];
    }
}

- (id _Nullable)objectForKey:(id)key {
    return self.keychainItemData[key];
}

#pragma mark — Internos

- (void)resetKeychainItem {
    // Remove item existente, se houver
    NSMutableDictionary *deleteQuery = [self dictionaryToSecItemFormat:self.keychainItemData];
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

    // Padrões mínimos
    self.keychainItemData = [@{
        (__bridge id)kSecAttrAccount:     @"",
        (__bridge id)kSecAttrLabel:       @"",
        (__bridge id)kSecAttrDescription: @"",
        (__bridge id)kSecValueData:       @""
    } mutableCopy];
}

- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert {
    // Prepara um dicionário para SecItemAdd/SecItemUpdate
    NSMutableDictionary *secItem = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    secItem[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    
    // Converte NSString em NSData para kSecValueData
    NSString *password = dictionaryToConvert[(__bridge id)kSecValueData];
    secItem[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    return secItem;
}

- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert {
    // Prepara uma query retornando kSecValueData
    NSMutableDictionary *returnDict = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    returnDict[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
    returnDict[(__bridge id)kSecClass]       = (__bridge id)kSecClassGenericPassword;

    CFDataRef passwordData = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)returnDict, (CFTypeRef *)&passwordData) == noErr) {
        [returnDict removeObjectForKey:(__bridge id)kSecReturnData];
        NSString *password = [[NSString alloc] initWithBytes:CFDataGetBytePtr(passwordData)
                                                      length:CFDataGetLength(passwordData)
                                                    encoding:NSUTF8StringEncoding];
        returnDict[(__bridge id)kSecValueData] = password;
        CFRelease(passwordData);
    }
    return returnDict;
}

- (void)writeToKeychain {
    CFDictionaryRef existing = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)self.genericPasswordQuery,
                                          (CFTypeRef *)&existing);
    if (status == errSecSuccess && existing) {
        // Atualiza
        NSMutableDictionary *updateItem = [NSMutableDictionary dictionaryWithDictionary:(__bridge NSDictionary *)existing];
        updateItem[(__bridge id)kSecClass] = self.genericPasswordQuery[(__bridge id)kSecClass];
        
        NSMutableDictionary *attributesToUpdate = [self dictionaryToSecItemFormat:self.keychainItemData];
        [attributesToUpdate removeObjectForKey:(__bridge id)kSecClass];
#if TARGET_IPHONE_SIMULATOR
        [attributesToUpdate removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
#endif
        SecItemUpdate((__bridge CFDictionaryRef)updateItem,
                      (__bridge CFDictionaryRef)attributesToUpdate);
        CFRelease(existing);
    } else {
        // Cria novo
        SecItemAdd((__bridge CFDictionaryRef)[self dictionaryToSecItemFormat:self.keychainItemData], NULL);
    }
}

@end

NS_ASSUME_NONNULL_END
