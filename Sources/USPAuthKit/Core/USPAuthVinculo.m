//
//  USPAuthVinculo.m
//  USPAuthKit
//
//  Created by Vagner Machado on 23/05/25.
//

#import "USPAuthVinculo.h"

@implementation USPAuthVinculo

- (instancetype)initWithDictionary:(NSDictionary<NSString*, id>*)dict {
    self = [super init];
    if (!self) return nil;
    
    _codigoSetor    = [dict[@"codigoSetor"]    integerValue];
    _codigoUnidade  = [dict[@"codigoUnidade"]  integerValue];
    _nomeUnidade    = [dict[@"nomeUnidade"]    ?: @"" copy];
    _nomeVinculo    = [dict[@"nomeVinculo"]    ?: @"" copy];
    _siglaUnidade   = [dict[@"siglaUnidade"]   ?: @"" copy];
    _tipoVinculo    = [dict[@"tipoVinculo"]    ?: @"" copy];
    
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:
      @"<Vínculo: %@ (%@) — setor %ld/%ld>",
      self.nomeVinculo,
      self.siglaUnidade,
      (long)self.codigoUnidade,
      (long)self.codigoSetor
    ];
}

@end
