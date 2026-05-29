/// Compile-time configuration for D-Assimp bindings.
///
/// Default is dynamic binding via bindbc-loader (runtime dlopen of
/// libassimp.so / assimp.dll). Add `versions: ["BindAssimp_Static"]` to
/// dub.json to switch to direct link-time binding against the import library
/// instead.
module bindbc.assimp.config;

version(BindAssimp_Static) enum staticBinding = true;
else                       enum staticBinding = false;
