//
//  USPAuthUser.m
//  USPAuthKit
//
//  Created by Vagner Machado on 23/05/25.
//

#import "USPAuthUser.h"
#import "USPAuthVinculo.h"

@implementation USPAuthUser

- (instancetype)initWithDictionary:(NSDictionary<NSString*,id>*)dict {
  self = [super init];
  if (!self) return nil;
  
  // Para cada campo, tenta extrair do dict; se não houver, armazena string vazia
  _loginUsuario             = [dict[@"loginUsuario"]             ?: @"" copy];
  _nomeUsuario              = [dict[@"nomeUsuario"]              ?: @"" copy];
  _emailPrincipalUsuario    = [dict[@"emailPrincipalUsuario"]    ?: @"" copy];
  _emailAlternativoUsuario  = [dict[@"emailAlternativoUsuario"]  ?: @"" copy];
  _emailUspUsuario          = [dict[@"emailUspUsuario"]          ?: @"" copy];
  _numeroTelefoneFormatado  = [dict[@"numeroTelefoneFormatado"]  ?: @"" copy];
  _tipoUsuario              = [dict[@"tipoUsuario"]              ?: @"" copy];
  _wsuserid                 = [dict[@"wsuserid"]                 ?: @"" copy];
  
  // Parse dos vínculos
  id raw = dict[@"vinculo"];
  if ([raw isKindOfClass:[NSArray class]]) {
    NSMutableArray<USPAuthVinculo*> *arr = [NSMutableArray array];
    for (id item in raw) {
      if ([item isKindOfClass:[NSDictionary class]]) {
        USPAuthVinculo *v = [[USPAuthVinculo alloc] initWithDictionary:item];
        [arr addObject:v];
      }
    }
    _vinculos = [arr copy];
  } else {
    _vinculos = @[];
  }
  
  return self;
}

- (NSString *)description {
    NSMutableString *s = [NSMutableString stringWithFormat:
        @"<User: %@ (%@)>", self.nomeUsuario, self.wsuserid
    ];
    [s appendString:@"\nVínculos:"];
    for (USPAuthVinculo *v in self.vinculos) {
        [s appendFormat:@"\n  %@", v];
    }
    return s;
}

@end
