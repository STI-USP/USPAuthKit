//
//  USPAuthUser.h
//  USPAuthKit
//
//  Created by Vagner Machado on 23/05/25.
//

#import <Foundation/Foundation.h>
@class USPAuthVinculo;

NS_ASSUME_NONNULL_BEGIN

@interface USPAuthUser : NSObject

@property (nonatomic, copy, readonly) NSString *loginUsuario;
@property (nonatomic, copy, readonly) NSString *nomeUsuario;
@property (nonatomic, copy, readonly) NSString *emailPrincipalUsuario;
@property (nonatomic, copy, readonly) NSString *emailAlternativoUsuario;
@property (nonatomic, copy, readonly) NSString *emailUspUsuario;
@property (nonatomic, copy, readonly) NSString *numeroTelefoneFormatado;
@property (nonatomic, copy, readonly) NSString *tipoUsuario;
@property (nonatomic, copy, readonly) NSString *wsuserid;
@property (nonatomic, copy, readonly) NSArray<USPAuthVinculo*> *vinculos;

/// Cria o usuário a partir de um dicionário JSON.
- (instancetype)initWithDictionary:(NSDictionary<NSString*,id>*)dict;

@end

NS_ASSUME_NONNULL_END
