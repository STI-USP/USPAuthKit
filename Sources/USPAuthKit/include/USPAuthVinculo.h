//
//  USPAuthVinculo.h
//  USPAuthKit
//
//  Created by Vagner Machado on 23/05/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface USPAuthVinculo : NSObject

@property (nonatomic, assign, readonly) NSInteger codigoSetor;
@property (nonatomic, assign, readonly) NSInteger codigoUnidade;
@property (nonatomic, copy, readonly) NSString *nomeUnidade;
@property (nonatomic, copy, readonly) NSString *nomeVinculo;
@property (nonatomic, copy, readonly) NSString *siglaUnidade;
@property (nonatomic, copy, readonly) NSString *tipoVinculo;

/// Cria um vínculo a partir do dicionário JSON
- (instancetype)initWithDictionary:(NSDictionary<NSString*, id>*)dict;

@end

NS_ASSUME_NONNULL_END
