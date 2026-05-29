/// Re-export of bindbc-common's binding codegen, parameterised for assimp.
///
/// `bind/core.d` (generated) does `mixin(joinFnBinds(...))`. Whether that
/// produces static `extern(C)` decls or dynamic function pointers + a
/// `bindModuleSymbols(lib)` loader is controlled by `staticBinding` from
/// `bindbc.assimp.config`.
module bindbc.assimp.codegen;

import bindbc.assimp.config: staticBinding;
import bindbc.common.codegen;

mixin(makeFnBindFns(staticBinding));
